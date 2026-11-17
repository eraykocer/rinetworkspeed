//
//  GatewayResolverTests.swift
//  rinetworkspeedTests
//
//  Parsing of routing table messages into the default gateway. The messages
//  are built by hand with the same layout the kernel returns.
//

import Testing
@testable import rinetworkspeed

struct GatewayResolverTests {

    private static let wifi: UInt16 = 4
    private static let cellular: UInt16 = 7

    private static let up: Int32 = 0x1
    private static let gatewayFlag: Int32 = 0x2
    private static let destinationBit: Int32 = 0x1
    private static let gatewayBit: Int32 = 0x2
    private static let netmaskBit: Int32 = 0x4

    // MARK: - Builders

    /// A `sockaddr_in` with the given length (16 for a full one).
    private static func ipv4(_ octets: [UInt8], length: UInt8 = 16) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = length
        bytes[1] = 2 // AF_INET
        for (i, octet) in octets.enumerated() { bytes[4 + i] = octet }
        return Array(bytes.prefix(Int(length)))
    }

    /// A link-layer `sockaddr_dl` gateway, used by routes without a router.
    private static func linkLayer() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 20
        bytes[1] = 18 // AF_LINK
        return bytes
    }

    /// One routing message: a 92-byte `rt_msghdr` followed by the addresses,
    /// each padded to 4 bytes.
    private static func message(index: UInt16, flags: Int32, addresses: Int32,
                                sockaddrs: [[UInt8]], version: UInt8 = 5) -> [UInt8] {
        var body: [UInt8] = []
        for sockaddr in sockaddrs {
            body += sockaddr
            body += [UInt8](repeating: 0, count: GatewayResolver.roundUp(sockaddr.count) - sockaddr.count)
        }
        var header = [UInt8](repeating: 0, count: GatewayResolver.headerSize)
        put(UInt16(header.count + body.count), into: &header, at: 0)
        header[2] = version
        header[3] = 4 // RTM_GET
        put(index, into: &header, at: 4)
        put(flags, into: &header, at: 8)
        put(addresses, into: &header, at: 12)
        return header + body
    }

    private static func put<T: FixedWidthInteger>(_ value: T, into bytes: inout [UInt8], at offset: Int) {
        withUnsafeBytes(of: value) { raw in
            for (i, byte) in raw.enumerated() { bytes[offset + i] = byte }
        }
    }

    private static func defaultRoute(index: UInt16, gateway: [UInt8]) -> [UInt8] {
        message(index: index, flags: up | gatewayFlag,
                addresses: destinationBit | gatewayBit | netmaskBit,
                sockaddrs: [ipv4([0, 0, 0, 0]), ipv4(gateway), ipv4([0, 0, 0, 0], length: 0)])
    }

    // MARK: - Tests

    @Test func roundUpPadsToFourBytes() {
        #expect(GatewayResolver.roundUp(0) == 4)
        #expect(GatewayResolver.roundUp(1) == 4)
        #expect(GatewayResolver.roundUp(4) == 4)
        #expect(GatewayResolver.roundUp(5) == 8)
        #expect(GatewayResolver.roundUp(16) == 16)
        #expect(GatewayResolver.roundUp(20) == 20)
    }

    @Test func routerThatIsNotTheFirstHost() {
        let table = Self.defaultRoute(index: Self.wifi, gateway: [192, 168, 1, 254])
        #expect(GatewayResolver.parseDefaultGateway(table, interfaceIndex: Self.wifi) == "192.168.1.254")
    }

    @Test func picksTheWiFiRouteWhenCellularComesFirst() {
        let table = Self.defaultRoute(index: Self.cellular, gateway: [10, 64, 64, 64])
            + Self.defaultRoute(index: Self.wifi, gateway: [192, 168, 0, 1])
        #expect(GatewayResolver.parseDefaultGateway(table, interfaceIndex: Self.wifi) == "192.168.0.1")
    }

    @Test func skipsRoutesThatAreNotDefault() {
        let subnetRoute = Self.message(index: Self.wifi, flags: Self.up | Self.gatewayFlag,
                                       addresses: Self.destinationBit | Self.gatewayBit,
                                       sockaddrs: [Self.ipv4([172, 16, 0, 0]), Self.ipv4([192, 168, 1, 2])])
        let table = subnetRoute + Self.defaultRoute(index: Self.wifi, gateway: [192, 168, 1, 1])
        #expect(GatewayResolver.parseDefaultGateway(table, interfaceIndex: Self.wifi) == "192.168.1.1")
    }

    @Test func shortenedDefaultDestination() {
        // The kernel may send the default destination with length 0.
        let table = Self.message(index: Self.wifi, flags: Self.up | Self.gatewayFlag,
                                 addresses: Self.destinationBit | Self.gatewayBit,
                                 sockaddrs: [Self.ipv4([0, 0, 0, 0], length: 0), Self.ipv4([10, 0, 0, 138])])
        #expect(GatewayResolver.parseDefaultGateway(table, interfaceIndex: Self.wifi) == "10.0.0.138")
    }

    @Test func linkLayerGatewayIsNotARouter() {
        let table = Self.message(index: Self.wifi, flags: Self.up | Self.gatewayFlag,
                                 addresses: Self.destinationBit | Self.gatewayBit,
                                 sockaddrs: [Self.ipv4([0, 0, 0, 0]), Self.linkLayer()])
        #expect(GatewayResolver.parseDefaultGateway(table, interfaceIndex: Self.wifi) == nil)
    }

    @Test func routeThatIsDownIsIgnored() {
        let table = Self.message(index: Self.wifi, flags: Self.gatewayFlag,
                                 addresses: Self.destinationBit | Self.gatewayBit,
                                 sockaddrs: [Self.ipv4([0, 0, 0, 0]), Self.ipv4([192, 168, 1, 1])])
        #expect(GatewayResolver.parseDefaultGateway(table, interfaceIndex: Self.wifi) == nil)
    }

    @Test func unknownMessageVersionIsIgnored() {
        let table = Self.message(index: Self.wifi, flags: Self.up | Self.gatewayFlag,
                                 addresses: Self.destinationBit | Self.gatewayBit,
                                 sockaddrs: [Self.ipv4([0, 0, 0, 0]), Self.ipv4([192, 168, 1, 1])],
                                 version: 9)
        #expect(GatewayResolver.parseDefaultGateway(table, interfaceIndex: Self.wifi) == nil)
    }

    @Test func noRouteForTheInterface() {
        let table = Self.defaultRoute(index: Self.cellular, gateway: [10, 64, 64, 64])
        #expect(GatewayResolver.parseDefaultGateway(table, interfaceIndex: Self.wifi) == nil)
    }

    @Test func malformedDataDoesNotCrash() {
        #expect(GatewayResolver.parseDefaultGateway([], interfaceIndex: Self.wifi) == nil)
        #expect(GatewayResolver.parseDefaultGateway([UInt8](repeating: 0xFF, count: 40), interfaceIndex: Self.wifi) == nil)

        // Header claims more bytes than there are.
        var truncated = Self.defaultRoute(index: Self.wifi, gateway: [192, 168, 1, 1])
        truncated.removeLast(8)
        #expect(GatewayResolver.parseDefaultGateway(truncated, interfaceIndex: Self.wifi) == nil)

        // Length shorter than a header.
        var tooShort = [UInt8](repeating: 0, count: 120)
        tooShort[0] = 10
        #expect(GatewayResolver.parseDefaultGateway(tooShort, interfaceIndex: Self.wifi) == nil)
    }
}
