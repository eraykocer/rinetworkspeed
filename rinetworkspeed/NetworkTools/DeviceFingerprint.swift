//
//  DeviceFingerprint.swift
//  rinetworkspeed
//
//  Names and kinds for devices on the local network, from what they announce
//  or answer themselves:
//  - Bonjour (mDNS) service names and TXT records, which carry model names
//    and on AirPlay devices the MAC address;
//  - NetBIOS node status over unicast UDP 137, which gives Windows and Samba
//    devices' names and MAC address;
//  - SSDP / UPnP device descriptions (friendly name, maker, model);
//  - the title and Server header of a device's web page.
//
//  iOS hides MAC addresses from apps, so these are the only ways to get one.
//

import Foundation
import Network
import Darwin

// MARK: - Identity

nonisolated enum DeviceKind: String, Codable, Equatable, Sendable {
    case router, phone, tablet, computer, tv, speaker, printer, camera, storage, smartHome
}

nonisolated struct DeviceIdentity: Equatable, Sendable {
    /// Name the device gives itself ("Living Room", "ERAY-PC").
    var name: String?
    var model: String?
    var manufacturer: String?
    /// "AA:BB:CC:DD:EE:FF", upper case.
    var mac: String?
    var kind: DeviceKind?
    /// Where the information came from, for example "_airplay._tcp", "NetBIOS", "UPnP", "HTTP".
    var sources: Set<String> = []
    /// Free text that helps guessing the kind (service types, UPnP device type, web page title).
    var hints: [String] = []

    /// Fills missing fields from `other`; the first source to name a field wins.
    mutating func merge(_ other: DeviceIdentity) {
        name = name ?? other.name
        model = model ?? other.model
        manufacturer = manufacturer ?? other.manufacturer
        mac = mac ?? other.mac
        sources.formUnion(other.sources)
        hints += other.hints.filter { !hints.contains($0) }
        kind = DeviceIdentity.guessKind(self) ?? kind ?? other.kind
    }

    /// "Model · Maker" for a subtitle, when either is known.
    var detail: String? {
        let parts = [model, manufacturer].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// MAC addresses with the "locally administered" bit set are random
    /// (private Wi-Fi addresses), so their first half says nothing about the maker.
    var hasPrivateMAC: Bool {
        guard let mac, let first = UInt8(mac.prefix(2), radix: 16) else { return false }
        return first & 0x02 != 0
    }

    // MARK: Kind

    /// Rules on the lower-cased model, maker, name and hints; the first match wins.
    static func guessKind(_ identity: DeviceIdentity) -> DeviceKind? {
        let text = ([identity.model, identity.manufacturer, identity.name].compactMap { $0 } + identity.hints)
            .joined(separator: " ")
            .lowercased()
        guard !text.isEmpty else { return nil }

        let rules: [(DeviceKind, [String])] = [
            (.camera, ["camera", "ipcam", "hikvision", "dahua", "ezviz", "reolink", "imou", "hap-category:17", "networkvideotransmitter"]),
            (.printer, ["_ipp.", "_ipps.", "_printer.", "_pdl-datastream.", "printer", "laserjet", "deskjet", "officejet", "envy", "epson", "brother", "canon", "kyocera", "xerox"]),
            (.tv, ["appletv", "apple tv", "chromecast", "_googlecast.", "bravia", "webos", "tizen", "roku", "firetv", "fire tv", "android tv", "smart tv", "television", " tv"]),
            (.speaker, ["audioaccessory", "homepod", "sonos", "_sonos.", "speaker", "echo dot", "soundbar"]),
            (.storage, ["synology", "diskstation", "qnap", "nas", "_afpovertcp.", "time capsule"]),
            (.tablet, ["ipad", "tablet", "galaxy tab"]),
            (.phone, ["iphone", "android", "galaxy", "pixel", "redmi", "oneplus", "phone"]),
            (.computer, ["macbook", "imac", "macmini", "mac mini", "macpro", "mac studio", "windows", "desktop", "laptop", "thinkpad", "_workstation.", "netbios", "_smb."]),
            (.router, ["internetgatewaydevice", "router", "gateway", "fritz", "modem", "access point", "mesh", "deco", "_airport."]),
            (.smartHome, ["_hap.", "_homekit.", "_matter", "hue", "tuya", "shelly", "tasmota", "esp32", "esp8266", "smart plug", "bulb", "thermostat"])
        ]
        for (kind, needles) in rules where needles.contains(where: { text.contains($0) }) {
            return kind
        }
        return nil
    }

    /// Normalises "a4:2b:b0:1:2:33", "A42BB0010233" and "a4-2b-…" to "A4:2B:B0:01:02:33".
    static func normalizedMAC(_ raw: String) -> String? {
        let parts = raw.split(whereSeparator: { $0 == ":" || $0 == "-" })
        let bytes: [UInt8]
        if parts.count == 6 {
            bytes = parts.compactMap { UInt8($0, radix: 16) }
        } else if parts.count == 1, raw.count == 12 {
            bytes = stride(from: 0, to: 12, by: 2).compactMap { offset in
                let start = raw.index(raw.startIndex, offsetBy: offset)
                return UInt8(raw[start..<raw.index(start, offsetBy: 2)], radix: 16)
            }
        } else {
            return nil
        }
        guard bytes.count == 6, bytes.contains(where: { $0 != 0 }), bytes != [UInt8](repeating: 0xFF, count: 6) else { return nil }
        return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

// MARK: - Bonjour TXT records

nonisolated enum BonjourFingerprint {
    /// Service types browsed. Each must also be listed under NSBonjourServices in Info.plist.
    static let serviceTypes = [
        "_airplay._tcp", "_raop._tcp", "_googlecast._tcp", "_companion-link._tcp",
        "_hap._tcp", "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp",
        "_smb._tcp", "_afpovertcp._tcp", "_workstation._tcp", "_sonos._tcp", "_spotify-connect._tcp"
    ]

    /// Identity from one service instance and its TXT record.
    static func identity(serviceName: String, type: String, txt: [String: String]) -> DeviceIdentity {
        var identity = DeviceIdentity()
        identity.sources = [type]
        identity.hints = [type + "."]
        let lowered = Dictionary(txt.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })

        var name = serviceName
        // RAOP instances are named "A1B2C3D4E5F6@Living Room": MAC, then name.
        if type.hasPrefix("_raop"), let at = serviceName.firstIndex(of: "@") {
            identity.mac = DeviceIdentity.normalizedMAC(String(serviceName[..<at]))
            name = String(serviceName[serviceName.index(after: at)...])
        }
        // "_workstation" instances are "name [aa:bb:cc:dd:ee:ff]".
        if type.hasPrefix("_workstation"), let open = serviceName.lastIndex(of: "["), serviceName.hasSuffix("]") {
            identity.mac = DeviceIdentity.normalizedMAC(String(serviceName[serviceName.index(after: open)..<serviceName.index(before: serviceName.endIndex)]))
            name = serviceName[..<open].trimmingCharacters(in: .whitespaces)
        }
        identity.name = name.isEmpty ? nil : name

        switch type {
        case let t where t.hasPrefix("_airplay"):
            identity.model = lowered["model"]
            identity.mac = identity.mac ?? lowered["deviceid"].flatMap(DeviceIdentity.normalizedMAC)
            if let model = identity.model, ["AppleTV", "AudioAccessory", "Mac"].contains(where: { model.hasPrefix($0) }) {
                identity.manufacturer = "Apple"
            }
        case let t where t.hasPrefix("_raop"):
            identity.model = lowered["am"]
        case let t where t.hasPrefix("_googlecast"):
            identity.name = lowered["fn"] ?? identity.name
            identity.model = lowered["md"]
            identity.manufacturer = "Google Cast"
        case let t where t.hasPrefix("_companion-link"):
            identity.model = lowered["rpmd"]
            identity.manufacturer = "Apple"
        case let t where t.hasPrefix("_hap"):
            identity.model = lowered["md"]
            if let category = lowered["ci"] { identity.hints.append("hap-category:\(category)") }
        case let t where t.hasPrefix("_ipp") || t.hasPrefix("_printer") || t.hasPrefix("_pdl"):
            identity.model = lowered["ty"] ?? lowered["product"]?.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            identity.manufacturer = lowered["usb_mfg"]
        default:
            identity.model = lowered["model"] ?? lowered["md"]
        }
        if identity.model?.isEmpty == true { identity.model = nil }
        identity.kind = DeviceIdentity.guessKind(identity)
        return identity
    }
}

// MARK: - NetBIOS

nonisolated enum NetBIOSFingerprint {
    /// Node status request for the wildcard name "*" (RFC 1002, 4.2.17).
    static func nodeStatusRequest(transactionID: UInt16) -> [UInt8] {
        var packet: [UInt8] = [
            UInt8(transactionID >> 8), UInt8(transactionID & 0xFF),
            0x00, 0x00,       // flags: query
            0x00, 0x01,       // one question
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ]
        // "*" followed by 15 zero bytes, each half-byte encoded as 'A' + value.
        var name = [UInt8](repeating: 0, count: 16)
        name[0] = UInt8(ascii: "*")
        packet.append(0x20)
        for byte in name {
            packet.append(UInt8(ascii: "A") + (byte >> 4))
            packet.append(UInt8(ascii: "A") + (byte & 0x0F))
        }
        packet.append(0x00)
        packet += [0x00, 0x21, 0x00, 0x01] // NBSTAT, IN
        return packet
    }

    /// Computer name, workgroup and MAC from a node status response.
    static func parse(_ data: [UInt8]) -> (name: String?, workgroup: String?, mac: String?)? {
        guard data.count > 12, data[2] & 0x80 != 0 else { return nil } // must be a response
        var offset = 12
        // Answer name: labels, or a two-byte pointer.
        while offset < data.count {
            let length = Int(data[offset])
            if length == 0 { offset += 1; break }
            if length & 0xC0 == 0xC0 { offset += 2; break }
            offset += 1 + length
        }
        offset += 10 // type, class, TTL, data length
        guard offset < data.count else { return nil }

        let count = Int(data[offset])
        offset += 1
        guard data.count >= offset + count * 18 else { return nil }

        var name: String?
        var workgroup: String?
        for index in 0..<count {
            let entry = offset + index * 18
            let raw = data[entry..<entry + 15]
            let text = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespaces.union(.controlCharacters))
            let suffix = data[entry + 15]
            let isGroup = data[entry + 16] & 0x80 != 0
            guard suffix == 0x00, !text.isEmpty else { continue }
            if isGroup {
                workgroup = workgroup ?? text
            } else {
                name = name ?? text
            }
        }

        var mac: String?
        let macStart = offset + count * 18
        if data.count >= macStart + 6 {
            mac = DeviceIdentity.normalizedMAC(data[macStart..<macStart + 6].map { String(format: "%02X", $0) }.joined(separator: ":"))
        }
        return (name, workgroup, mac)
    }
}

// MARK: - Web page

nonisolated enum HTTPFingerprint {
    /// Text of the page's <title>, whitespace collapsed; nil when missing or empty.
    static func title(in html: String) -> String? {
        guard let start = html.range(of: "<title", options: .caseInsensitive),
              let close = html.range(of: ">", range: start.upperBound..<html.endIndex),
              let end = html.range(of: "</title>", options: .caseInsensitive, range: close.upperBound..<html.endIndex) else { return nil }
        let title = html[close.upperBound..<end.lowerBound]
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return title.isEmpty ? nil : title
    }
}

// MARK: - Discovery

/// Runs the discovery methods and returns identities by IPv4 address.
@MainActor
enum DeviceFingerprinter {
    /// Listens for Bonjour and SSDP announcements for `duration` seconds.
    /// Finds devices that answer no TCP port too.
    static func discoverAnnouncements(interfaceAddress: String?, duration: TimeInterval = 4) async -> [String: DeviceIdentity] {
        async let bonjour = BonjourScanner().run(duration: duration)
        async let upnp = upnpIdentities(interfaceAddress: interfaceAddress)
        var result = await bonjour
        for (ip, identity) in await upnp {
            result[ip, default: DeviceIdentity()].merge(identity)
        }
        return result
    }

    /// Asks each address for its NetBIOS name and, for `webAddresses`, reads
    /// the web page title.
    static func identify(addresses: [String], webAddresses: [String: Int]) async -> [String: DeviceIdentity] {
        async let netbios = NetBIOSScanner.query(addresses)
        var result = await netbios
        await withTaskGroup(of: (String, DeviceIdentity?).self) { group in
            for (address, port) in webAddresses {
                group.addTask { (address, await webIdentity(address: address, port: port)) }
            }
            for await (address, identity) in group {
                if let identity { result[address, default: DeviceIdentity()].merge(identity) }
            }
        }
        return result
    }

    private static func upnpIdentities(interfaceAddress: String?) async -> [String: DeviceIdentity] {
        let answers = await SSDP.discover(gateway: nil, interfaceAddress: interfaceAddress, timeout: 3, targets: ["ssdp:all"])
        var locations: [String: URL] = [:]
        for answer in answers where locations[answer.from] == nil {
            locations[answer.from] = answer.response.location
        }

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var result: [String: DeviceIdentity] = [:]
        await withTaskGroup(of: (String, DeviceIdentity?).self) { group in
            for (address, location) in locations.prefix(24) {
                group.addTask {
                    var request = URLRequest(url: location)
                    request.timeoutInterval = 3
                    guard let (data, _) = try? await session.data(for: request),
                          let description = UPnPDescription.parse(data, location: location) else { return (address, nil) }
                    var identity = DeviceIdentity()
                    identity.name = description.friendlyName
                    identity.model = description.modelName
                    identity.manufacturer = description.manufacturer
                    identity.sources = ["UPnP"]
                    identity.hints = description.deviceType.map { [$0] } ?? []
                    identity.kind = DeviceIdentity.guessKind(identity)
                    return (address, identity)
                }
            }
            for await (address, identity) in group {
                if let identity { result[address] = identity }
            }
        }
        return result
    }

    private static func webIdentity(address: String, port: Int) async -> DeviceIdentity? {
        guard let url = URL(string: "\(port == 443 ? "https" : "http")://\(address)\(port == 80 || port == 443 ? "" : ":\(port)")/") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        var identity = DeviceIdentity()
        identity.sources = ["HTTP"]
        if let server = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Server") {
            identity.hints.append(server)
        }
        if let title = HTTPFingerprint.title(in: String(decoding: data.prefix(65_536), as: UTF8.self)) {
            identity.hints.append(title)
        }
        guard !identity.hints.isEmpty else { return nil }
        identity.kind = DeviceIdentity.guessKind(identity)
        return identity
    }
}

/// Browses the Bonjour service types and resolves each instance to its IPv4 address.
nonisolated private final class BonjourScanner: @unchecked Sendable {
    private struct Found {
        let endpoint: NWEndpoint
        let identity: DeviceIdentity
    }

    private let queue = DispatchQueue(label: "rinetworkspeed.fingerprint.bonjour")
    private let lock = NSLock()
    private var found: [String: Found] = [:]

    func run(duration: TimeInterval) async -> [String: DeviceIdentity] {
        let browsers = BonjourFingerprint.serviceTypes.map { type -> NWBrowser in
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: NWParameters())
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.record(results, type: type)
            }
            browser.start(queue: queue)
            return browser
        }
        try? await Task.sleep(for: .seconds(duration))
        browsers.forEach { $0.cancel() }

        lock.lock()
        let instances = Array(found.values.prefix(60))
        lock.unlock()

        var result: [String: DeviceIdentity] = [:]
        await withTaskGroup(of: (String?, DeviceIdentity).self) { group in
            for instance in instances {
                group.addTask { (await Self.resolveIPv4(instance.endpoint), instance.identity) }
            }
            for await (address, identity) in group {
                guard let address else { continue }
                result[address, default: DeviceIdentity()].merge(identity)
            }
        }
        return result
    }

    private func record(_ results: Set<NWBrowser.Result>, type: String) {
        lock.lock()
        defer { lock.unlock() }
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            var txt: [String: String] = [:]
            if case let .bonjour(record) = result.metadata {
                txt = record.dictionary
            }
            found["\(type)|\(name)"] = Found(
                endpoint: result.endpoint,
                identity: BonjourFingerprint.identity(serviceName: name, type: type, txt: txt)
            )
        }
    }

    /// Connects to the service over IPv4 and reads the address it reached.
    private static func resolveIPv4(_ endpoint: NWEndpoint) async -> String? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        let queue = DispatchQueue(label: "rinetworkspeed.fingerprint.resolve")
        return await withCheckedContinuation { continuation in
            let once = OnceContinuation<String?>(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host, _) = connection.currentPath?.remoteEndpoint,
                       case let .ipv4(address) = host {
                        once.resume("\(address)".split(separator: "%").first.map(String.init))
                    } else {
                        once.resume(nil)
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    once.resume(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 2) {
                once.resume(nil)
                connection.cancel()
            }
        }
    }
}

/// Sends NetBIOS node status requests to many addresses from one UDP socket.
nonisolated private enum NetBIOSScanner {
    static func query(_ addresses: [String], timeout: TimeInterval = 1.5) async -> [String: DeviceIdentity] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: queryBlocking(addresses, timeout: timeout))
            }
        }
    }

    private static func queryBlocking(_ addresses: [String], timeout: TimeInterval) -> [String: DeviceIdentity] {
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return [:] }
        defer { close(descriptor) }

        let request = NetBIOSFingerprint.nodeStatusRequest(transactionID: UInt16.random(in: 1...UInt16.max))
        for address in addresses {
            var target = sockaddr_in()
            target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            target.sin_family = sa_family_t(AF_INET)
            target.sin_port = UInt16(137).bigEndian
            guard inet_pton(AF_INET, address, &target.sin_addr) == 1 else { continue }
            _ = request.withUnsafeBytes { buffer in
                withUnsafePointer(to: &target) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(descriptor, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        var result: [String: DeviceIdentity] = [:]
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { break }
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, Int32(max(1, Double(deadline - now) / 1_000_000))) > 0 else { continue }

            var buffer = [UInt8](repeating: 0, count: 1024)
            var source = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = buffer.withUnsafeMutableBytes { bytes in
                withUnsafeMutablePointer(to: &source) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(descriptor, bytes.baseAddress, bytes.count, 0, $0, &sourceLength)
                    }
                }
            }
            guard count > 0, let parsed = NetBIOSFingerprint.parse(Array(buffer.prefix(count))) else { continue }

            var addressText = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var address = source.sin_addr
            guard inet_ntop(AF_INET, &address, &addressText, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }

            var identity = DeviceIdentity()
            identity.name = parsed.name
            identity.mac = parsed.mac
            identity.sources = ["NetBIOS"]
            identity.hints = ["netbios"]
            identity.kind = DeviceIdentity.guessKind(identity)
            result[String(cString: addressText)] = identity
        }
        return result
    }
}
