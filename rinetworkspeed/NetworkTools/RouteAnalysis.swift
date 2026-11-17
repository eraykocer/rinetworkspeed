//
//  RouteAnalysis.swift
//  rinetworkspeed
//
//  Per-hop statistics of a continuous trace (MTR style), the network an
//  address belongs to, and where lasting packet loss starts on the route.
//

import Foundation

// MARK: - Hop statistics

/// Autonomous system (network operator) an address belongs to.
nonisolated struct ASNInfo: Equatable, Sendable {
    let number: Int
    /// Short operator name, for example "Google LLC"; nil when unknown.
    let name: String?

    var label: String {
        name.map { "AS\(number) \($0)" } ?? "AS\(number)"
    }
}

/// One TTL of the route, accumulated over every round.
nonisolated struct RouteHop: Identifiable, Equatable, Sendable {
    let ttl: Int
    var id: Int { ttl }

    /// Every address that answered at this TTL, oldest first. Load-balanced
    /// routes can answer from more than one.
    private(set) var addresses: [String] = []
    var hostname: String?
    var asn: ASNInfo?
    /// True when the destination itself answers at this TTL.
    var isDestination = false

    private(set) var sent = 0
    private(set) var received = 0
    private(set) var last: Double?
    private(set) var best: Double?
    private(set) var worst: Double?
    private var total: Double = 0

    init(ttl: Int) {
        self.ttl = ttl
    }

    /// Latest address that answered.
    var address: String? { addresses.last }

    var average: Double? {
        received > 0 ? total / Double(received) : nil
    }

    /// Fraction of probes without an answer (0…1).
    var lossShare: Double {
        sent > 0 ? 1 - Double(received) / Double(sent) : 0
    }

    /// Adds one probe; nil means it was lost.
    mutating func record(_ reply: HopReply?) {
        sent += 1
        guard let reply else { return }
        received += 1
        total += reply.milliseconds
        last = reply.milliseconds
        best = min(best ?? reply.milliseconds, reply.milliseconds)
        worst = max(worst ?? reply.milliseconds, reply.milliseconds)
        if addresses.last != reply.address {
            addresses.removeAll { $0 == reply.address }
            addresses.append(reply.address)
        }
        if reply.reachedDestination {
            isDestination = true
        }
    }
}

// MARK: - Address scope

nonisolated enum IPv4Scope: Equatable, Sendable {
    /// 10/8, 172.16/12, 192.168/16: home and company networks.
    case privateNetwork
    /// 100.64/10: used by providers for carrier-grade NAT.
    case sharedAddressSpace
    /// Loopback, link-local and other addresses that are never routed.
    case special
    case publicInternet

    init?(_ address: String) {
        let parts = address.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4, address.split(separator: ".").count == 4 else { return nil }
        let (a, b) = (parts[0], parts[1])
        switch a {
        case 10:
            self = .privateNetwork
        case 172 where (16...31).contains(b):
            self = .privateNetwork
        case 192 where b == 168:
            self = .privateNetwork
        case 100 where (64...127).contains(b):
            self = .sharedAddressSpace
        case 0, 127, 224...255:
            self = .special
        case 169 where b == 254:
            self = .special
        default:
            self = .publicInternet
        }
    }
}

// MARK: - Finding

/// Where on the route a problem sits, in terms the user can act on.
nonisolated enum RouteSegment: Equatable, Sendable {
    /// Hop 1: the home router, so the Wi-Fi or the router itself.
    case homeNetwork
    /// A private or carrier-grade NAT address after the router: the
    /// provider's access network, or a second router at home.
    case accessNetwork
    /// A public address in the same network as the first public hop.
    case provider(ASNInfo?)
    /// A public address in a different network.
    case beyondProvider(ASNInfo)
}

nonisolated enum RouteFinding: Equatable, Sendable {
    /// Not enough rounds yet.
    case collecting
    /// The destination answers and loss to it is below the limit.
    case clean
    /// Loss that lasts until the destination starts at this hop.
    case lossStarts(hop: Int, segment: RouteSegment)
    /// The destination never answered, so loss to it cannot be measured.
    case destinationSilent

    /// Rounds needed before loss is judged.
    static let minimumProbes = 10
    /// Loss to the destination below this is normal.
    static let lossLimit = 0.03

    /// `hops` must be in TTL order and end at the destination when it answered.
    ///
    /// Many routers answer traceroute probes slowly or not at all, so loss at
    /// a hop only counts when it continues at every later hop that answers:
    /// walking back from the destination, a hop belongs to the lossy stretch
    /// while it loses at least half as much as the destination.
    static func evaluate(_ hops: [RouteHop]) -> RouteFinding {
        guard let destination = hops.last, destination.isDestination else {
            let rounds = hops.map(\.sent).max() ?? 0
            return rounds >= 3 ? .destinationSilent : .collecting
        }
        guard destination.sent >= minimumProbes else { return .collecting }

        let destinationLoss = destination.lossShare
        guard destinationLoss >= lossLimit else { return .clean }

        var origin = destination
        for hop in hops.dropLast().reversed() {
            // A router that never answers says nothing either way.
            guard hop.received > 0 else { continue }
            guard hop.lossShare >= destinationLoss / 2 else { break }
            origin = hop
        }
        return .lossStarts(hop: origin.ttl, segment: segment(of: origin, in: hops))
    }

    static func segment(of hop: RouteHop, in hops: [RouteHop]) -> RouteSegment {
        if hop.ttl == 1 { return .homeNetwork }
        guard let address = hop.address, IPv4Scope(address) == .publicInternet else {
            return .accessNetwork
        }
        let firstPublic = hops.first { $0.address.flatMap(IPv4Scope.init) == .publicInternet }
        if let asn = hop.asn, let providerASN = firstPublic?.asn, asn.number != providerASN.number {
            return .beyondProvider(asn)
        }
        return .provider(hop.asn ?? firstPublic?.asn)
    }
}

// MARK: - ASN lookup

/// Network operator of an address from Team Cymru's IP-to-ASN DNS service,
/// queried over Cloudflare's DNS-over-HTTPS (the DNS tool uses the same
/// endpoint). Only public addresses are looked up.
nonisolated enum ASNLookup {
    static func lookup(_ address: String) async -> ASNInfo? {
        guard IPv4Scope(address) == .publicInternet,
              let query = originQueryName(for: address),
              let originText = await txtRecord(query),
              let number = parseOrigin(originText) else { return nil }
        let name = await txtRecord("AS\(number).asn.cymru.com").flatMap(parseName)
        return ASNInfo(number: number, name: name)
    }

    /// "1.2.3.4" → "4.3.2.1.origin.asn.cymru.com".
    static func originQueryName(for address: String) -> String? {
        let parts = address.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) else { return nil }
        return parts.reversed().joined(separator: ".") + ".origin.asn.cymru.com"
    }

    /// `"15169 | 8.8.8.0/24 | US | arin | 2023-12-28"` → 15169. When an
    /// address is announced by several networks the first one is used.
    static func parseOrigin(_ text: String) -> Int? {
        let fields = unquoted(text).split(separator: "|")
        return fields.first?
            .split(separator: " ")
            .first
            .flatMap { Int($0) }
    }

    /// `"15169 | US | arin | 2000-03-30 | GOOGLE - Google LLC, US"` → "Google LLC".
    static func parseName(_ text: String) -> String? {
        let fields = unquoted(text).split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 5 else { return nil }
        var name = fields[4...].joined(separator: "|")

        // Drop the trailing country code (", US").
        if let comma = name.range(of: ", ", options: .backwards),
           name[comma.upperBound...].count == 2 {
            name = String(name[..<comma.lowerBound])
        }
        // "GOOGLE - Google LLC": keep the descriptive part.
        if let dash = name.range(of: " - ") {
            let description = name[dash.upperBound...].trimmingCharacters(in: .whitespaces)
            if !description.isEmpty { name = description }
        }
        return name.isEmpty ? nil : name
    }

    private static func unquoted(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// DNS JSON response; the record list is named "Answer" in the format.
    nonisolated private struct DNSResponse: Decodable {
        nonisolated struct Record: Decodable {
            let type: Int
            let data: String
        }
        let records: [Record]?

        enum CodingKeys: String, CodingKey {
            case records = "Answer"
        }
    }

    private static func txtRecord(_ name: String) async -> String? {
        guard var components = URLComponents(string: "https://cloudflare-dns.com/dns-query") else { return nil }
        components.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "type", value: "TXT")]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(DNSResponse.self, from: data) else { return nil }
        return response.records?.first { $0.type == 16 }?.data
    }
}
