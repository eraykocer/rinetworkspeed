//
//  RouteTracingTests.swift
//  rinetworkspeedTests
//
//  ICMP packet building and parsing, per-hop statistics, address scopes,
//  ASN text parsing and where lasting loss starts on a route.
//

import Testing
@testable import rinetworkspeed

struct ICMPPacketTests {

    @Test func echoRequestLayoutAndChecksum() {
        let packet = ICMPPacket.echoRequest(identifier: 0x1234, sequence: 0xABCD, payloadSize: 32)
        #expect(packet.count == 40)
        #expect(packet[0] == 8)
        #expect(packet[1] == 0)
        #expect(Array(packet[4...7]) == [0x12, 0x34, 0xAB, 0xCD])
        // A packet that contains its own checksum sums to zero.
        #expect(ICMPPacket.checksum(packet) == 0)
    }

    @Test func checksumMatchesRFC1071Example() {
        // RFC 1071 example words 0x0001 0xF203 0xF4F5 0xF6F7 sum to 0xDDF2 (folded); complement 0x220D.
        #expect(ICMPPacket.checksum([0x00, 0x01, 0xF2, 0x03, 0xF4, 0xF5, 0xF6, 0xF7]) == 0x220D)
        #expect(ICMPPacket.checksum([0xFF]) == 0x00FF)
    }

    /// A 20-byte IPv4 header carrying ICMP.
    private func ipv4Header() -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 20)
        header[0] = 0x45
        header[9] = 1
        return header
    }

    @Test func echoReplyWithAndWithoutIPHeader() {
        var reply = ICMPPacket.echoRequest(identifier: 7, sequence: 42)
        reply[0] = 0
        let expected = ICMPPacket.Reply(kind: .echoReply, identifier: 7, sequence: 42)
        #expect(ICMPPacket.parse(reply) == expected)
        #expect(ICMPPacket.parse(ipv4Header() + reply) == expected)
    }

    @Test func timeExceededCarriesTheOriginalProbe() {
        let probe = ICMPPacket.echoRequest(identifier: 9, sequence: 300)
        let message: [UInt8] = [11, 0, 0, 0, 0, 0, 0, 0] + ipv4Header() + Array(probe.prefix(8))
        let expected = ICMPPacket.Reply(kind: .timeExceeded, identifier: 9, sequence: 300)
        #expect(ICMPPacket.parse(ipv4Header() + message) == expected)
        #expect(ICMPPacket.parse(message) == expected)
    }

    @Test func unreachableIsRecognised() {
        let probe = ICMPPacket.echoRequest(identifier: 1, sequence: 2)
        let message: [UInt8] = [3, 3, 0, 0, 0, 0, 0, 0] + ipv4Header() + Array(probe.prefix(8))
        #expect(ICMPPacket.parse(message)?.kind == .unreachable)
    }

    @Test func rejectsOtherMessages() {
        #expect(ICMPPacket.parse([]) == nil)
        #expect(ICMPPacket.parse([0, 0, 0]) == nil)
        // An echo request is not an answer.
        #expect(ICMPPacket.parse(ICMPPacket.echoRequest(identifier: 1, sequence: 1)) == nil)
        // Time Exceeded for a UDP probe (not ours).
        var udpHeader = ipv4Header()
        udpHeader[9] = 17
        let foreign: [UInt8] = [11, 0, 0, 0, 0, 0, 0, 0] + udpHeader + [0, 53, 0, 53, 0, 8, 0, 0]
        #expect(ICMPPacket.parse(foreign) == nil)
        // Truncated original probe.
        let truncated: [UInt8] = [11, 0, 0, 0, 0, 0, 0, 0] + ipv4Header() + [8, 0, 0]
        #expect(ICMPPacket.parse(truncated) == nil)
    }
}

struct RouteHopTests {

    @Test func accumulatesProbes() {
        var hop = RouteHop(ttl: 3)
        hop.record(HopReply(address: "10.0.0.1", milliseconds: 10, reachedDestination: false))
        hop.record(nil)
        hop.record(HopReply(address: "10.0.0.2", milliseconds: 30, reachedDestination: false))
        hop.record(HopReply(address: "10.0.0.1", milliseconds: 20, reachedDestination: false))
        #expect(hop.sent == 4)
        #expect(hop.received == 3)
        #expect(hop.lossShare == 0.25)
        #expect(hop.average == 20)
        #expect(hop.best == 10)
        #expect(hop.worst == 30)
        #expect(hop.last == 20)
        #expect(hop.addresses == ["10.0.0.2", "10.0.0.1"])
        #expect(hop.address == "10.0.0.1")
        #expect(!hop.isDestination)
    }

    @Test func echoReplyMarksTheDestination() {
        var hop = RouteHop(ttl: 9)
        hop.record(HopReply(address: "1.1.1.1", milliseconds: 12, reachedDestination: true))
        #expect(hop.isDestination)
    }
}

struct IPv4ScopeTests {

    @Test(arguments: [
        ("10.1.2.3", IPv4Scope.privateNetwork),
        ("172.16.0.1", IPv4Scope.privateNetwork),
        ("172.31.255.1", IPv4Scope.privateNetwork),
        ("172.32.0.1", IPv4Scope.publicInternet),
        ("192.168.1.1", IPv4Scope.privateNetwork),
        ("100.64.0.1", IPv4Scope.sharedAddressSpace),
        ("100.127.255.1", IPv4Scope.sharedAddressSpace),
        ("100.128.0.1", IPv4Scope.publicInternet),
        ("169.254.1.1", IPv4Scope.special),
        ("127.0.0.1", IPv4Scope.special),
        ("8.8.8.8", IPv4Scope.publicInternet)
    ])
    func classifies(address: String, scope: IPv4Scope) {
        #expect(IPv4Scope(address) == scope)
    }

    @Test func rejectsInvalidAddresses() {
        #expect(IPv4Scope("1.2.3") == nil)
        #expect(IPv4Scope("1.2.3.256") == nil)
        #expect(IPv4Scope("example.com") == nil)
    }
}

struct ASNLookupParsingTests {

    @Test func originQueryName() {
        #expect(ASNLookup.originQueryName(for: "8.8.4.4") == "4.4.8.8.origin.asn.cymru.com")
        #expect(ASNLookup.originQueryName(for: "nope") == nil)
    }

    @Test func parsesOrigin() {
        #expect(ASNLookup.parseOrigin("\"15169 | 8.8.8.0/24 | US | arin | 2023-12-28\"") == 15169)
        #expect(ASNLookup.parseOrigin("\"9121 47331 | 85.96.0.0/12 | TR | ripencc | 2005-03-31\"") == 9121)
        #expect(ASNLookup.parseOrigin("\"\"") == nil)
    }

    @Test func parsesName() {
        #expect(ASNLookup.parseName("\"15169 | US | arin | 2000-03-30 | GOOGLE - Google LLC, US\"") == "Google LLC")
        #expect(ASNLookup.parseName("\"13335 | US | arin | 2010-07-14 | CLOUDFLARENET, US\"") == "CLOUDFLARENET")
        #expect(ASNLookup.parseName("\"15169 | US\"") == nil)
    }
}

struct RouteFindingTests {
    private let provider = ASNInfo(number: 9121, name: "Provider")
    private let other = ASNInfo(number: 13335, name: "Other")

    /// A hop answering `answered` of `sent` probes from `address`.
    private func hop(_ ttl: Int, _ address: String?, sent: Int = 20, answered: Int? = nil,
                     destination: Bool = false, asn: ASNInfo? = nil) -> RouteHop {
        var hop = RouteHop(ttl: ttl)
        let answers = address == nil ? 0 : (answered ?? sent)
        for i in 0..<sent {
            if i < answers, let address {
                hop.record(HopReply(address: address, milliseconds: Double(ttl * 5), reachedDestination: destination))
            } else {
                hop.record(nil)
            }
        }
        hop.asn = asn
        return hop
    }

    @Test func waitsForRounds() {
        let route = [hop(1, "192.168.1.1", sent: 5), hop(2, "8.8.8.8", sent: 5, destination: true)]
        #expect(RouteFinding.evaluate(route) == .collecting)
        #expect(RouteFinding.evaluate([]) == .collecting)
    }

    @Test func cleanRoute() {
        let route = [hop(1, "192.168.1.1"), hop(2, "85.1.1.1", answered: 20), hop(3, "8.8.8.8", destination: true)]
        #expect(RouteFinding.evaluate(route) == .clean)
    }

    @Test func silentDestination() {
        let route = [hop(1, "192.168.1.1", sent: 3), hop(2, nil, sent: 3)]
        #expect(RouteFinding.evaluate(route) == .destinationSilent)
    }

    @Test func rateLimitedMiddleHopIsIgnored() {
        // Hop 2 loses 50 % but hop 3 and the destination lose nothing.
        let route = [
            hop(1, "192.168.1.1"),
            hop(2, "85.1.1.1", answered: 10, asn: provider),
            hop(3, "85.1.2.1", asn: provider),
            hop(4, "8.8.8.8", destination: true, asn: other)
        ]
        #expect(RouteFinding.evaluate(route) == .clean)
    }

    @Test func lossFromTheRouter() {
        let route = [
            hop(1, "192.168.1.1", answered: 16),
            hop(2, "85.1.1.1", answered: 17, asn: provider),
            hop(3, "8.8.8.8", answered: 16, destination: true, asn: other)
        ]
        #expect(RouteFinding.evaluate(route) == .lossStarts(hop: 1, segment: .homeNetwork))
    }

    @Test func lossInsideTheProviderSkippingSilentHops() {
        let route = [
            hop(1, "192.168.1.1"),
            hop(2, "85.1.1.1", asn: provider),
            hop(3, "85.1.2.1", answered: 16, asn: provider),
            hop(4, nil),
            hop(5, "8.8.8.8", answered: 17, destination: true, asn: other)
        ]
        #expect(RouteFinding.evaluate(route) == .lossStarts(hop: 3, segment: .provider(provider)))
    }

    @Test func lossBeyondTheProvider() {
        let route = [
            hop(1, "192.168.1.1"),
            hop(2, "85.1.1.1", asn: provider),
            hop(3, "1.0.0.1", answered: 16, asn: other),
            hop(4, "1.1.1.1", answered: 16, destination: true, asn: other)
        ]
        #expect(RouteFinding.evaluate(route) == .lossStarts(hop: 3, segment: .beyondProvider(other)))
    }

    @Test func lossAtAPrivateAddressAfterTheRouter() {
        let route = [
            hop(1, "192.168.1.1"),
            hop(2, "100.70.0.1", answered: 17),
            hop(3, "8.8.8.8", answered: 17, destination: true, asn: other)
        ]
        #expect(RouteFinding.evaluate(route) == .lossStarts(hop: 2, segment: .accessNetwork))
    }
}
