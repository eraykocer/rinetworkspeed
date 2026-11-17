//
//  NATTypeView.swift
//  rinetworkspeed
//
//  NAT type (as game consoles report it), carrier-grade NAT and double NAT.
//  STUN (RFC 5389) from one UDP socket to two servers shows whether the NAT
//  keeps the same public port for every destination; the router's WAN address
//  (UPnP) or the first hops of a trace show NAT layers.
//

import SwiftUI
import Combine
import Darwin

// MARK: - STUN

nonisolated enum STUN {
    static let magicCookie: UInt32 = 0x2112_A442

    static func bindingRequest(transactionID: [UInt8]) -> [UInt8] {
        precondition(transactionID.count == 12)
        return [0x00, 0x01, 0x00, 0x00, 0x21, 0x12, 0xA4, 0x42] + transactionID
    }

    /// Mapped address and port from a Binding success response for `transactionID`.
    static func parseMappedAddress(_ data: [UInt8], transactionID: [UInt8]) -> (address: String, port: UInt16)? {
        guard data.count >= 20, data[0] == 0x01, data[1] == 0x01,
              Array(data[4..<8]) == [0x21, 0x12, 0xA4, 0x42],
              Array(data[8..<20]) == transactionID else { return nil }
        let length = Int(UInt16(data[2]) << 8 | UInt16(data[3]))
        let end = min(data.count, 20 + length)
        var offset = 20
        var plain: (String, UInt16)?
        while offset + 4 <= end {
            let type = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            let attributeLength = Int(UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3]))
            let value = offset + 4
            guard value + attributeLength <= end else { break }
            if attributeLength >= 8, data[value + 1] == 0x01 { // IPv4
                var port = UInt16(data[value + 2]) << 8 | UInt16(data[value + 3])
                var octets = Array(data[(value + 4)..<(value + 8)])
                if type == 0x0020 { // XOR-MAPPED-ADDRESS
                    port ^= UInt16(magicCookie >> 16)
                    let cookie: [UInt8] = [0x21, 0x12, 0xA4, 0x42]
                    octets = zip(octets, cookie).map { $0 ^ $1 }
                    return (octets.map { String($0) }.joined(separator: "."), port)
                }
                if type == 0x0001 { // MAPPED-ADDRESS
                    plain = (octets.map { String($0) }.joined(separator: "."), port)
                }
            }
            offset = value + ((attributeLength + 3) / 4) * 4
        }
        return plain
    }

    /// Sends a Binding request to each server (IPv4 address and port) from
    /// the same local port and returns what each saw; nil entries did not answer.
    static func query(servers: [(address: String, port: UInt16)], timeout: TimeInterval = 2) async -> [(address: String, port: UInt16)?] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: queryBlocking(servers: servers, timeout: timeout))
            }
        }
    }

    private static func queryBlocking(servers: [(address: String, port: UInt16)], timeout: TimeInterval) -> [(address: String, port: UInt16)?] {
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return servers.map { _ in nil } }
        defer { close(descriptor) }

        var results: [(address: String, port: UInt16)?] = []
        for server in servers {
            let transaction = (0..<12).map { _ in UInt8.random(in: 0...255) }
            let request = bindingRequest(transactionID: transaction)
            var target = sockaddr_in()
            target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            target.sin_family = sa_family_t(AF_INET)
            target.sin_port = server.port.bigEndian
            guard inet_pton(AF_INET, server.address, &target.sin_addr) == 1 else { results.append(nil); continue }

            var answer: (address: String, port: UInt16)?
            // Two tries, as UDP can drop a packet.
            for _ in 0..<2 where answer == nil {
                _ = request.withUnsafeBytes { buffer in
                    withUnsafePointer(to: &target) { pointer in
                        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(descriptor, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout / 2 * 1_000_000_000)
                while answer == nil {
                    let now = DispatchTime.now().uptimeNanoseconds
                    guard now < deadline else { break }
                    var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                    guard poll(&poller, 1, Int32(max(1, Double(deadline - now) / 1_000_000))) > 0 else { continue }
                    var buffer = [UInt8](repeating: 0, count: 1024)
                    let capacity = buffer.count
                    let count = recv(descriptor, &buffer, capacity, 0)
                    if count > 0 {
                        answer = parseMappedAddress(Array(buffer.prefix(count)), transactionID: transaction)
                    }
                }
            }
            results.append(answer)
        }
        return results
    }
}

// MARK: - Analysis

nonisolated enum NATAnalysis {
    nonisolated enum Mapping: Equatable, Sendable {
        /// Same public address and port towards every server.
        case endpointIndependent
        /// A different public port per destination (symmetric NAT).
        case endpointDependent
        /// Only one server answered.
        case unknown
        /// No server answered: UDP is blocked.
        case blocked
    }

    nonisolated enum Layers: Equatable, Sendable {
        /// The router has a public address: port forwarding can work.
        case publicAddress
        /// The provider shares a public address (100.64.0.0/10 or a router
        /// address that differs from the public one).
        case carrierGradeNAT
        /// A second router in front of this one (private WAN address).
        case doubleNAT
        case unknown
    }

    static func mapping(_ answers: [(address: String, port: UInt16)?]) -> Mapping {
        let answered = answers.compactMap { $0 }
        if answered.isEmpty { return .blocked }
        guard answered.count >= 2 else { return .unknown }
        let first = answered[0]
        return answered.allSatisfy({ $0.address == first.address && $0.port == first.port }) ? .endpointIndependent : .endpointDependent
    }

    /// - Parameters:
    ///   - routerWAN: the router's internet address from UPnP, when known.
    ///   - publicAddress: what the internet sees (STUN).
    ///   - earlyHops: addresses of trace hops 2, 3, … (hop 1 is the router).
    static func layers(routerWAN: String?, publicAddress: String?, earlyHops: [String]) -> Layers {
        if let routerWAN, let scope = IPv4Scope(routerWAN) {
            switch scope {
            case .sharedAddressSpace: return .carrierGradeNAT
            case .privateNetwork: return .doubleNAT
            case .publicInternet:
                if let publicAddress, publicAddress != routerWAN { return .carrierGradeNAT }
                return .publicAddress
            case .special: break
            }
        }
        // Without UPnP: a provider's NAT shows as 100.64/10 hops, a second
        // home router as a private hop right after the first.
        if earlyHops.contains(where: { IPv4Scope($0) == .sharedAddressSpace }) { return .carrierGradeNAT }
        if let second = earlyHops.first, IPv4Scope(second) == .privateNetwork { return .doubleNAT }
        if !earlyHops.isEmpty { return .publicAddress }
        return .unknown
    }
}

// MARK: - ViewModel

@MainActor
final class NATTypeViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var mapping: NATAnalysis.Mapping?
    @Published private(set) var layers: NATAnalysis.Layers?
    @Published private(set) var publicAddress: String?
    @Published private(set) var routerWAN: String?

    private var task: Task<Void, Never>?

    func start() {
        task?.cancel()
        mapping = nil
        layers = nil
        publicAddress = nil
        routerWAN = nil
        isRunning = true
        task = Task {
            defer { isRunning = false }
            let details = WiFiInfoManager.localInterfaceDetails()

            // Two STUN servers at different addresses and ports, asked from
            // the same local port.
            async let google = TracerouteViewModel.resolveHost("stun.l.google.com")
            async let cloudflare = TracerouteViewModel.resolveHost("stun.cloudflare.com")
            let resolved = [(await google, UInt16(19302)), (await cloudflare, UInt16(3478))]
            let servers = resolved.compactMap { address, port in address.map { (address: $0, port: port) } }
            let answers = await STUN.query(servers: servers)
            mapping = NATAnalysis.mapping(answers + [(address: String, port: UInt16)?](repeating: nil, count: max(0, 2 - servers.count)))
            publicAddress = answers.compactMap { $0 }.first?.address
            guard !Task.isCancelled else { return }

            if details.ipAddress != nil {
                routerWAN = (try? await UPnPGateway.read(gateway: details.routerIP, interfaceAddress: details.ipAddress))?.externalIP
            }
            var hops: [String] = []
            if routerWAN == nil, let tracer = ICMPTracer(destination: "1.1.1.1") {
                let replies = await tracer.round(ttls: 1...4, timeout: 1.5)
                hops = (2...4).compactMap { replies[$0]?.address }
            }
            layers = NATAnalysis.layers(routerWAN: routerWAN, publicAddress: publicAddress, earlyHops: hops)
        }
    }

    func cancel() {
        task?.cancel()
        isRunning = false
    }
}

// MARK: - View

struct NATTypeView: View {
    @StateObject private var vm = NATTypeViewModel()
    private let tint = Color(red: 0.55, green: 0.42, blue: 0.98)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                ToolHero(icon: "arrow.left.arrow.right.circle.fill", title: "NAT Type",
                         subtitle: "What game consoles call Open, Moderate or Strict, and whether your provider shares your address (CGNAT).",
                         tint: tint, isRunning: vm.isRunning, startTitle: "Check NAT") {
                    vm.isRunning ? vm.cancel() : vm.start()
                }

                if let mapping = vm.mapping {
                    AppSection("Results") {
                        mappingRow(mapping)
                        if let layers = vm.layers {
                            AppRowDivider(leadingInset: 16)
                            layersRow(layers)
                        }
                        if let address = vm.publicAddress {
                            AppRowDivider(leadingInset: 16)
                            CheckRow(status: .info, title: Text("Public address"), value: address)
                        }
                        if let wan = vm.routerWAN {
                            AppRowDivider(leadingInset: 16)
                            CheckRow(status: .info, title: Text("Router's internet address"), value: wan)
                        }
                    }
                }

                NoteCard(status: .info, title: Text("About these results"),
                         message: Text("Consoles also test whether unsolicited incoming traffic gets through, which needs a server this app doesn't have. Open usually requires UPnP or port forwarding on the router, and is impossible behind carrier-grade NAT unless the provider gives you a public address."))
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .appPageBackground()
        .navigationTitle("NAT Type")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vm.cancel() }
    }

    private func mappingRow(_ mapping: NATAnalysis.Mapping) -> some View {
        switch mapping {
        case .endpointIndependent:
            return CheckRow(status: .pass, title: Text("NAT type: Open or Moderate"),
                            detail: Text("Your public port stays the same for every server, so games and calls can connect directly."))
        case .endpointDependent:
            return CheckRow(status: .warning, title: Text("NAT type: Strict"),
                            detail: Text("Your public port changes per server (symmetric NAT). Games may fail to match you with others and voice chat may not connect."))
        case .unknown:
            return CheckRow(status: .info, title: Text("NAT type: unknown"),
                            detail: Text("Only one test server answered."))
        case .blocked:
            return CheckRow(status: .fail, title: Text("UDP is blocked"),
                            detail: Text("No test server answered over UDP. Online games and calls will struggle on this network."))
        }
    }

    private func layersRow(_ layers: NATAnalysis.Layers) -> some View {
        switch layers {
        case .publicAddress:
            return CheckRow(status: .pass, title: Text("No carrier-grade NAT"),
                            detail: Text("Your router has its own public address, so port forwarding can work."))
        case .carrierGradeNAT:
            return CheckRow(status: .warning, title: Text("Carrier-grade NAT"),
                            detail: Text("Your provider shares one public address between several customers. Port forwarding won't work; ask the provider for a public (static or dynamic) IP if you need it."))
        case .doubleNAT:
            return CheckRow(status: .warning, title: Text("Double NAT"),
                            detail: Text("Another router sits in front of yours. Put the provider's modem in bridge mode, or forward ports on both."))
        case .unknown:
            return CheckRow(status: .info, title: Text("NAT layers: unknown"),
                            detail: Text("The router didn't answer UPnP and the trace gave no clear answer."))
        }
    }
}
