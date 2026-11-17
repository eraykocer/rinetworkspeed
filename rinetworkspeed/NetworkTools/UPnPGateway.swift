//
//  UPnPGateway.swift
//  rinetworkspeed
//
//  Reads line and connection details from the router over UPnP IGD: SSDP
//  discovery (multicast, needs the multicast networking entitlement), the
//  device description, then SOAP calls to the WAN services.
//

import Foundation
import Darwin

// MARK: - Reading

/// What the router reported. Every field is optional because routers
/// implement different parts of the standard.
nonisolated struct ModemReading: Codable, Equatable, Sendable {
    nonisolated struct PortMapping: Codable, Equatable, Sendable {
        let externalPort: Int
        let transport: String
        let internalClient: String
        let internalPort: Int
        let description: String?
        let enabled: Bool
    }

    var date = Date()
    var routerAddress: String?
    var friendlyName: String?
    var manufacturer: String?
    var modelName: String?
    /// "DSL", "Ethernet", "Cable", "POTS" or "Other".
    var accessType: String?
    /// "Up", "Down", "Initializing" or "Unavailable".
    var linkStatus: String?
    var downstreamBitsPerSecond: Int64?
    var upstreamBitsPerSecond: Int64?
    var externalIP: String?
    var connectionStatus: String?
    var uptimeSeconds: Int?
    /// Since the router last restarted; 32-bit counters on many routers, so
    /// they wrap around after 4 GB.
    var totalBytesReceived: Int64?
    var totalBytesSent: Int64?
    var portMappings: [PortMapping] = []

    /// On DSL the layer-1 rate is the line's sync rate. On an Ethernet WAN it
    /// is only the speed of the cable to the next device.
    var isLineRate: Bool {
        accessType?.uppercased().contains("DSL") == true
    }

    var downstreamMbps: Double? { downstreamBitsPerSecond.map { Double($0) / 1_000_000 } }
    var upstreamMbps: Double? { upstreamBitsPerSecond.map { Double($0) / 1_000_000 } }
}

// MARK: - Errors

nonisolated enum UPnPError: Error, Equatable {
    /// No router answered the SSDP search.
    case notFound
    /// The device description could not be loaded or read.
    case descriptionUnavailable
    /// The router has no WAN services in its description.
    case noWANService
}

// MARK: - Gateway

nonisolated enum UPnPGateway {
    static let wanCommonService = "urn:schemas-upnp-org:service:WANCommonInterfaceConfig:"
    static let wanIPService = "urn:schemas-upnp-org:service:WANIPConnection:"
    static let wanPPPService = "urn:schemas-upnp-org:service:WANPPPConnection:"
    /// Port mappings read at most, so a broken router cannot loop forever.
    static let maxPortMappings = 64

    /// Discovers the router and reads everything it offers.
    /// - Parameters:
    ///   - gateway: the default gateway; its answer is preferred when several
    ///     UPnP devices answer.
    ///   - interfaceAddress: the Wi-Fi address, so the search leaves on Wi-Fi.
    static func read(gateway: String?, interfaceAddress: String?) async throws -> ModemReading {
        let answers = await SSDP.discover(gateway: gateway, interfaceAddress: interfaceAddress, timeout: 3)
        guard let answer = answers.first(where: { $0.from == gateway }) ?? answers.first else {
            throw UPnPError.notFound
        }

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: answer.response.location)
        request.timeoutInterval = 5
        guard let (data, _) = try? await session.data(for: request),
              let description = UPnPDescription.parse(data, location: answer.response.location) else {
            throw UPnPError.descriptionUnavailable
        }

        var reading = ModemReading()
        reading.routerAddress = answer.from
        reading.friendlyName = description.friendlyName
        reading.manufacturer = description.manufacturer
        reading.modelName = description.modelName

        let common = description.service(prefix: wanCommonService)
        let connection = description.service(prefix: wanIPService) ?? description.service(prefix: wanPPPService)
        guard common != nil || connection != nil else { throw UPnPError.noWANService }

        if let common {
            if let link = await call(session, common, "GetCommonLinkProperties") {
                reading.accessType = link["NewWANAccessType"]
                reading.linkStatus = link["NewPhysicalLinkStatus"]
                reading.downstreamBitsPerSecond = link["NewLayer1DownstreamMaxBitRate"].flatMap { Int64($0) }
                reading.upstreamBitsPerSecond = link["NewLayer1UpstreamMaxBitRate"].flatMap { Int64($0) }
            }
            reading.totalBytesReceived = await call(session, common, "GetTotalBytesReceived")?["NewTotalBytesReceived"].flatMap { Int64($0) }
            reading.totalBytesSent = await call(session, common, "GetTotalBytesSent")?["NewTotalBytesSent"].flatMap { Int64($0) }
        }

        if let connection {
            reading.externalIP = await call(session, connection, "GetExternalIPAddress")?["NewExternalIPAddress"]
            if let status = await call(session, connection, "GetStatusInfo") {
                reading.connectionStatus = status["NewConnectionStatus"]
                reading.uptimeSeconds = status["NewUptime"].flatMap { Int($0) }
            }
            for index in 0..<maxPortMappings {
                guard let entry = await call(session, connection, "GetGenericPortMappingEntry",
                                             arguments: [("NewPortMappingIndex", String(index))]),
                      let mapping = UPnPSOAP.portMapping(from: entry) else { break }
                reading.portMappings.append(mapping)
            }
        }
        return reading
    }

    /// One SOAP action; nil when it failed or the router answered with a fault.
    private static func call(_ session: URLSession, _ service: UPnPDescription.Service, _ action: String,
                             arguments: [(String, String)] = []) async -> [String: String]? {
        var request = URLRequest(url: service.controlURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service.type)#\(action)\"", forHTTPHeaderField: "SOAPAction")
        request.httpBody = Data(UPnPSOAP.envelope(action: action, service: service.type, arguments: arguments).utf8)

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UPnPSOAP.parseResponse(data)
    }
}

// MARK: - SSDP

nonisolated enum SSDP {
    static let multicastAddress = "239.255.255.250"
    static let port: UInt16 = 1900
    static let searchTargets = [
        "urn:schemas-upnp-org:device:InternetGatewayDevice:1",
        "urn:schemas-upnp-org:device:InternetGatewayDevice:2"
    ]

    nonisolated struct Response: Equatable, Sendable {
        let location: URL
        let searchTarget: String?
        let server: String?
    }

    static func searchMessage(target: String) -> String {
        [
            "M-SEARCH * HTTP/1.1",
            "HOST: \(multicastAddress):\(port)",
            "MAN: \"ssdp:discover\"",
            "MX: 2",
            "ST: \(target)",
            "", ""
        ].joined(separator: "\r\n")
    }

    /// Parses an "HTTP/1.1 200 OK" search response; header names are case-insensitive.
    static func parseResponse(_ text: String) -> Response? {
        let lines = text.components(separatedBy: "\r\n").flatMap { $0.components(separatedBy: "\n") }
        guard let status = lines.first, status.uppercased().hasPrefix("HTTP/1.1 200") else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        guard let location = headers["LOCATION"].flatMap(URL.init(string:)),
              location.scheme == "http" || location.scheme == "https" else { return nil }
        return Response(location: location, searchTarget: headers["ST"], server: headers["SERVER"])
    }

    /// Sends the searches to the multicast group and, for routers that only
    /// answer directly, to the gateway, then collects answers until `timeout`.
    /// - Parameter targets: search targets; the router's device types by
    ///   default, "ssdp:all" to hear from every UPnP device.
    static func discover(gateway: String?, interfaceAddress: String?, timeout: TimeInterval,
                         targets: [String] = searchTargets) async -> [(from: String, response: Response)] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: discoverBlocking(gateway: gateway, interfaceAddress: interfaceAddress,
                                                                timeout: timeout, targets: targets))
            }
        }
    }

    private static func discoverBlocking(gateway: String?, interfaceAddress: String?, timeout: TimeInterval,
                                         targets: [String]) -> [(from: String, response: Response)] {
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

        let destinations = [multicastAddress] + (gateway.map { [$0] } ?? [])
        // UDP can drop a packet, so every search goes out twice.
        for _ in 0..<2 {
            for target in targets {
                let message = Array(searchMessage(target: target).utf8)
                for destination in destinations {
                    send(message, to: destination, descriptor: descriptor)
                }
            }
        }

        var answers: [(from: String, response: Response)] = []
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { break }
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let waitMilliseconds = Int32(max(1, Double(deadline - now) / 1_000_000))
            guard poll(&poller, 1, waitMilliseconds) > 0 else { continue }

            var buffer = [UInt8](repeating: 0, count: 4096)
            var source = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = buffer.withUnsafeMutableBytes { bytes in
                withUnsafeMutablePointer(to: &source) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(descriptor, bytes.baseAddress, bytes.count, 0, $0, &sourceLength)
                    }
                }
            }
            guard count > 0,
                  let text = String(bytes: buffer.prefix(count), encoding: .utf8),
                  let response = parseResponse(text) else { continue }

            var addressText = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var address = source.sin_addr
            guard inet_ntop(AF_INET, &address, &addressText, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let from = String(cString: addressText)
            if !answers.contains(where: { $0.from == from && $0.response.location == response.location }) {
                answers.append((from, response))
            }
        }
        return answers
    }

    private static func send(_ message: [UInt8], to host: String, descriptor: Int32) {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return }
        _ = message.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}

// MARK: - Device description

nonisolated struct UPnPDescription: Equatable, Sendable {
    nonisolated struct Service: Equatable, Sendable {
        /// For example "urn:schemas-upnp-org:service:WANIPConnection:1".
        let type: String
        let controlURL: URL
    }

    /// Type of the root device, for example "urn:schemas-upnp-org:device:MediaRenderer:1".
    var deviceType: String?
    var friendlyName: String?
    var manufacturer: String?
    var modelName: String?
    var services: [Service] = []

    /// First service whose type starts with `prefix` (any version).
    func service(prefix: String) -> Service? {
        services.first { $0.type.hasPrefix(prefix) }
    }

    /// Parses the device description. Control URLs are resolved against
    /// `URLBase` when present, otherwise against the description's location.
    static func parse(_ data: Data, location: URL) -> UPnPDescription? {
        let collector = DescriptionCollector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = collector
        guard parser.parse() else { return nil }

        let base = collector.urlBase.flatMap { URL(string: $0) } ?? location
        var description = UPnPDescription()
        description.deviceType = collector.deviceType
        description.friendlyName = collector.friendlyName
        description.manufacturer = collector.manufacturer
        description.modelName = collector.modelName
        description.services = collector.services.compactMap { type, control in
            guard let url = URL(string: control, relativeTo: base)?.absoluteURL else { return nil }
            return Service(type: type, controlURL: url)
        }
        return description
    }

    nonisolated private final class DescriptionCollector: NSObject, XMLParserDelegate {
        var urlBase: String?
        var deviceType: String?
        var friendlyName: String?
        var manufacturer: String?
        var modelName: String?
        var services: [(type: String, control: String)] = []

        private var text = ""
        private var serviceType: String?
        private var controlURL: String?
        private var inService = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            if elementName == "service" {
                inService = true
                serviceType = nil
                controlURL = nil
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = ""
            switch elementName {
            case "service":
                if let serviceType, let controlURL {
                    services.append((serviceType, controlURL))
                }
                inService = false
            case "serviceType" where inService:
                serviceType = value
            case "controlURL" where inService:
                controlURL = value
            // The root device comes first, so the first value of each wins.
            case "deviceType" where deviceType == nil && !value.isEmpty:
                deviceType = value
            case "friendlyName" where friendlyName == nil && !value.isEmpty:
                friendlyName = value
            case "manufacturer" where manufacturer == nil && !value.isEmpty:
                manufacturer = value
            case "modelName" where modelName == nil && !value.isEmpty:
                modelName = value
            case "URLBase" where !value.isEmpty:
                urlBase = value
            default:
                break
            }
        }
    }
}

// MARK: - SOAP

nonisolated enum UPnPSOAP {
    static func envelope(action: String, service: String, arguments: [(String, String)]) -> String {
        let body = arguments.map { "<\($0)>\(escaped($1))</\($0)>" }.joined()
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body><u:\(action) xmlns:u="\(service)">\(body)</u:\(action)></s:Body></s:Envelope>
        """
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Text of every element in the response by its local name; nil for a SOAP fault.
    static func parseResponse(_ data: Data) -> [String: String]? {
        let collector = ValueCollector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = collector
        guard parser.parse(), !collector.isFault else { return nil }
        return collector.values
    }

    /// One entry of GetGenericPortMappingEntry; nil when required fields are missing.
    static func portMapping(from values: [String: String]) -> ModemReading.PortMapping? {
        guard let external = values["NewExternalPort"].flatMap({ Int($0) }),
              let transport = values["NewProtocol"],
              let client = values["NewInternalClient"],
              let internalPort = values["NewInternalPort"].flatMap({ Int($0) }) else { return nil }
        let description = values["NewPortMappingDescription"].flatMap { $0.isEmpty ? nil : $0 }
        let enabled = values["NewEnabled"].map { $0 == "1" || $0.lowercased() == "true" } ?? true
        return ModemReading.PortMapping(externalPort: external, transport: transport, internalClient: client,
                                        internalPort: internalPort, description: description, enabled: enabled)
    }

    nonisolated private final class ValueCollector: NSObject, XMLParserDelegate {
        var values: [String: String] = [:]
        var isFault = false
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            if elementName == "Fault" { isFault = true }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                values[elementName] = value
            }
            text = ""
        }
    }
}
