//
//  CameraFinder.swift
//  rinetworkspeed
//
//  Looks for network cameras on the Wi-Fi network (for example in a rented
//  flat or hotel room): ports cameras use for video streams, ONVIF discovery,
//  and devices that announce themselves as cameras. It can only see cameras
//  on the same network.
//

import SwiftUI
import Combine
import Darwin

// MARK: - Evidence

nonisolated struct CameraSuspect: Identifiable, Equatable, Sendable {
    nonisolated enum Level: Int, Comparable, Sendable {
        case possible, likely
        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    nonisolated enum Reason: Equatable, Sendable {
        /// A video stream port (RTSP) is open.
        case videoStream(UInt16)
        /// A port used by a camera maker's own software is open.
        case makerPort(UInt16, maker: String)
        /// The device answered an ONVIF camera search.
        case onvif
        /// The device calls itself a camera (Bonjour, UPnP, web page).
        case announcedAsCamera
        /// The device names a camera maker.
        case cameraMaker(String)
    }

    var id: String { address }
    let address: String
    var name: String?
    var detail: String?
    let level: Level
    let reasons: [Reason]
}

nonisolated enum CameraEvidence {
    static let videoStreamPorts: [UInt16] = [554, 8554]
    static let makerPorts: [UInt16: String] = [8000: "Hikvision", 37777: "Dahua", 34567: "XMEye", 9527: "XMEye"]
    static var allPorts: [UInt16] { videoStreamPorts + makerPorts.keys.sorted() }
    /// Matched as whole words, so "arlo" doesn't match "Carlo's iPhone".
    static let cameraMakers = ["hikvision", "dahua", "ezviz", "reolink", "imou", "tapo", "wyze", "arlo", "foscam",
                               "uniview", "annke", "eufycam", "yi camera", "blink camera", "ring doorbell", "ring camera"]

    /// Combines what was found about one address; nil when nothing points to a camera.
    static func assess(address: String, openPorts: Set<UInt16>, identity: DeviceIdentity?, answeredONVIF: Bool) -> CameraSuspect? {
        var reasons: [CameraSuspect.Reason] = []
        for port in videoStreamPorts where openPorts.contains(port) {
            reasons.append(.videoStream(port))
        }
        for (port, maker) in makerPorts.sorted(by: { $0.key < $1.key }) where openPorts.contains(port) {
            reasons.append(.makerPort(port, maker: maker))
        }
        if answeredONVIF {
            reasons.append(.onvif)
        }
        if identity?.kind == .camera {
            reasons.append(.announcedAsCamera)
        }
        let words = [identity?.manufacturer, identity?.model, identity?.name].compactMap { $0 }.joined(separator: " ")
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
        let makerText = " " + String(words).split(separator: " ").joined(separator: " ") + " "
        if let maker = cameraMakers.first(where: { makerText.contains(" \($0) ") }) {
            reasons.append(.cameraMaker(maker))
        }
        guard !reasons.isEmpty else { return nil }

        // A maker port alone (8000 is also used by many web apps) is only a possibility.
        let strong = reasons.contains { reason in
            if case .makerPort = reason { return false }
            return true
        }
        return CameraSuspect(address: address, name: identity?.name, detail: identity?.detail,
                             level: strong ? .likely : .possible, reasons: reasons)
    }

    /// WS-Discovery probe for ONVIF video devices.
    static func onvifProbe(messageID: UUID = UUID()) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>\
        <e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing" \
        xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" xmlns:dn="http://www.onvif.org/ver10/network/wsdl">\
        <e:Header><w:MessageID>uuid:\(messageID.uuidString.lowercased())</w:MessageID>\
        <w:To e:mustUnderstand="true">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>\
        <w:Action e:mustUnderstand="true">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action></e:Header>\
        <e:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe></e:Body></e:Envelope>
        """
    }

    /// True for a ProbeMatch from a video device.
    static func isONVIFMatch(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("probematch") && (lowered.contains("networkvideotransmitter") || lowered.contains("onvif"))
    }
}

// MARK: - Multicast exchange

nonisolated enum UDPMulticast {
    /// Sends `message` to a multicast group and collects the answers until `timeout`.
    static func exchange(_ message: String, group: String, port: UInt16, interfaceAddress: String?,
                         timeout: TimeInterval) async -> [(from: String, text: String)] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: exchangeBlocking(message, group: group, port: port,
                                                                interfaceAddress: interfaceAddress, timeout: timeout))
            }
        }
    }

    private static func exchangeBlocking(_ message: String, group: String, port: UInt16, interfaceAddress: String?,
                                         timeout: TimeInterval) -> [(from: String, text: String)] {
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return [] }
        defer { close(descriptor) }

        var ttl: UInt8 = 2
        setsockopt(descriptor, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        if let interfaceAddress {
            var interface = in_addr()
            if inet_pton(AF_INET, interfaceAddress, &interface) == 1 {
                setsockopt(descriptor, IPPROTO_IP, IP_MULTICAST_IF, &interface, socklen_t(MemoryLayout<in_addr>.size))
            }
        }

        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = port.bigEndian
        guard inet_pton(AF_INET, group, &target.sin_addr) == 1 else { return [] }
        let bytes = Array(message.utf8)
        for _ in 0..<2 {
            _ = bytes.withUnsafeBytes { buffer in
                withUnsafePointer(to: &target) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(descriptor, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var answers: [(from: String, text: String)] = []
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { break }
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, Int32(max(1, Double(deadline - now) / 1_000_000))) > 0 else { continue }

            var buffer = [UInt8](repeating: 0, count: 8192)
            var source = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = buffer.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &source) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(descriptor, raw.baseAddress, raw.count, 0, $0, &sourceLength)
                    }
                }
            }
            guard count > 0 else { continue }
            var addressText = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var address = source.sin_addr
            guard inet_ntop(AF_INET, &address, &addressText, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            answers.append((String(cString: addressText), String(decoding: buffer.prefix(count), as: UTF8.self)))
        }
        return answers
    }
}

// MARK: - ViewModel

@MainActor
final class CameraFinderViewModel: ObservableObject {
    @Published private(set) var isScanning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var suspects: [CameraSuspect] = []
    @Published private(set) var scannedDevices = 0
    @Published private(set) var hasScanned = false
    @Published private(set) var notOnWiFi = false

    private var task: Task<Void, Never>?

    func start() {
        task?.cancel()
        suspects = []
        progress = 0
        scannedDevices = 0
        notOnWiFi = false
        isScanning = true

        task = Task {
            defer { isScanning = false }
            let details = WiFiInfoManager.localInterfaceDetails()
            guard let own = details.ipAddress else {
                notOnWiFi = true
                return
            }
            let parts = own.split(separator: ".")
            guard parts.count == 4 else { return }
            let base = parts.prefix(3).joined(separator: ".")

            async let announcements = DeviceFingerprinter.discoverAnnouncements(interfaceAddress: own)
            async let onvif = UDPMulticast.exchange(CameraEvidence.onvifProbe(), group: "239.255.255.250", port: 3702,
                                                    interfaceAddress: own, timeout: 3)

            // Every address on the /24, every camera port.
            let addresses = (1...254).map { "\(base).\($0)" }.filter { $0 != own }
            var openPorts: [String: Set<UInt16>] = [:]
            let batches = stride(from: 0, to: addresses.count, by: 25).map { Array(addresses[$0..<min($0 + 25, addresses.count)]) }
            for (index, batch) in batches.enumerated() {
                guard !Task.isCancelled else { return }
                await withTaskGroup(of: (String, UInt16, Bool).self) { group in
                    for address in batch {
                        for port in CameraEvidence.allPorts {
                            group.addTask {
                                let ms = await PingMonitor.tcpConnectTime(host: address, port: port, timeout: 0.8)
                                return (address, port, ms >= 0)
                            }
                        }
                    }
                    for await (address, port, open) in group where open {
                        openPorts[address, default: []].insert(port)
                    }
                }
                progress = Double(index + 1) / Double(batches.count)
            }

            let identities = await announcements
            let onvifAnswers = Set(await onvif.filter { CameraEvidence.isONVIFMatch($0.text) }.map(\.from))
            guard !Task.isCancelled else { return }

            let candidates = Set(openPorts.keys).union(identities.keys).union(onvifAnswers)
                .filter { $0.hasPrefix(base + ".") && $0 != own }
            scannedDevices = candidates.count
            suspects = candidates.compactMap { address in
                CameraEvidence.assess(address: address, openPorts: openPorts[address] ?? [],
                                      identity: identities[address], answeredONVIF: onvifAnswers.contains(address))
            }
            .sorted { ($0.level, $1.address) > ($1.level, $0.address) }
            hasScanned = true
        }
    }

    func cancel() {
        task?.cancel()
        isScanning = false
    }
}

// MARK: - View

struct CameraFinderView: View {
    @StateObject private var vm = CameraFinderViewModel()
    private let tint = Color(red: 0.86, green: 0.25, blue: 0.35)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                ToolHero(icon: "web.camera.fill", title: "Hidden Camera Check",
                         subtitle: "Looks for cameras on this Wi-Fi network, for example in a rented flat or a hotel room.",
                         tint: tint, isRunning: vm.isScanning, startTitle: "Scan for Cameras") {
                    vm.isScanning ? vm.cancel() : vm.start()
                }

                if vm.isScanning {
                    ProgressView(value: vm.progress)
                        .tint(tint)
                }

                if vm.notOnWiFi {
                    NoteCard(status: .warning, title: Text("Not on Wi-Fi"),
                             message: Text("Join the Wi-Fi network you want to check, then scan again."))
                } else if vm.hasScanned && !vm.isScanning {
                    summary
                    if !vm.suspects.isEmpty {
                        AppSection("Possible Cameras") {
                            ForEach(vm.suspects) { suspect in
                                suspectRow(suspect)
                                if suspect.id != vm.suspects.last?.id { AppRowDivider(leadingInset: 16) }
                            }
                        }
                    }
                }

                NoteCard(status: .info, title: Text("What this can't see"),
                         message: Text("Only cameras on this Wi-Fi network are found. Cameras on another network, on mobile data or recording only to a memory card are invisible to any app. Also check the room itself: look for small lenses in smoke detectors, chargers and clocks, for example with your flashlight in the dark."))
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .appPageBackground()
        .navigationTitle("Hidden Camera Check")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vm.cancel() }
    }

    @ViewBuilder
    private var summary: some View {
        let likely = vm.suspects.filter { $0.level == .likely }.count
        if likely > 0 {
            NoteCard(status: .fail, title: Text("\(likely) likely cameras on this network"),
                     message: Text("These devices stream video or call themselves cameras. In a rental, ask the host where they are; cameras in bedrooms and bathrooms are not allowed on most platforms."))
        } else if !vm.suspects.isEmpty {
            NoteCard(status: .warning, title: Text("No clear camera, but some devices could be one"),
                     message: Text("They use ports camera makers use, which other devices use too. Check what they are."))
        } else {
            NoteCard(status: .pass, title: Text("No cameras found on this network"),
                     message: Text("\(vm.scannedDevices) devices checked. This doesn't rule out cameras on other networks."))
        }
    }

    private func suspectRow(_ suspect: CameraSuspect) -> some View {
        CheckRow(
            status: suspect.level == .likely ? .fail : .warning,
            title: Text(verbatim: suspect.name ?? suspect.address),
            detail: Text(verbatim: ([suspect.name == nil ? nil : suspect.address, suspect.detail].compactMap { $0 }
                                    + suspect.reasons.map(Self.describe)).joined(separator: "\n"))
        )
    }

    private static func describe(_ reason: CameraSuspect.Reason) -> String {
        switch reason {
        case .videoStream(let port): return String(localized: "Video stream port \(Int(port)) (RTSP) is open")
        case .makerPort(let port, let maker): return String(localized: "Port \(Int(port)) used by \(maker) cameras is open")
        case .onvif: return String(localized: "Answered a camera (ONVIF) search")
        case .announcedAsCamera: return String(localized: "Announces itself as a camera")
        case .cameraMaker(let maker): return String(localized: "Made by a camera maker (\(maker))")
        }
    }
}
