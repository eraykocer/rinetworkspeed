//
//  NetworkUtilityTests.swift
//  rinetworkspeedTests
//
//  Pure logic behind the network utilities: subnet math and Wake-on-LAN packets.
//

import Testing
@testable import rinetworkspeed

struct SubnetCalculationTests {

    @Test func typicalHomeSubnet() throws {
        let c = try #require(SubnetCalculation("192.168.1.10/24"))
        #expect(SubnetCalculation.format(c.network) == "192.168.1.0")
        #expect(SubnetCalculation.format(c.broadcast) == "192.168.1.255")
        #expect(SubnetCalculation.format(c.mask) == "255.255.255.0")
        #expect(SubnetCalculation.format(c.wildcard) == "0.0.0.255")
        #expect(SubnetCalculation.format(c.firstHost) == "192.168.1.1")
        #expect(SubnetCalculation.format(c.lastHost) == "192.168.1.254")
        #expect(c.usableHosts == 254)
        #expect(c.totalAddresses == 256)
    }

    @Test func nonOctetBoundary() throws {
        let c = try #require(SubnetCalculation("10.0.5.77/20"))
        #expect(SubnetCalculation.format(c.network) == "10.0.0.0")
        #expect(SubnetCalculation.format(c.broadcast) == "10.0.15.255")
        #expect(c.usableHosts == 4_094)
    }

    @Test func pointToPointAndSingleHost() throws {
        let p2p = try #require(SubnetCalculation("192.168.0.0/31"))
        #expect(p2p.usableHosts == 2)
        #expect(SubnetCalculation.format(p2p.firstHost) == "192.168.0.0")
        #expect(SubnetCalculation.format(p2p.lastHost) == "192.168.0.1")

        let host = try #require(SubnetCalculation("8.8.8.8/32"))
        #expect(host.usableHosts == 1)
    }

    @Test func wholeAddressSpace() throws {
        let c = try #require(SubnetCalculation("1.2.3.4/0"))
        #expect(c.mask == 0)
        #expect(c.totalAddresses == 4_294_967_296)
    }

    @Test func defaultPrefixWhenOmitted() throws {
        let c = try #require(SubnetCalculation("172.16.4.9"))
        #expect(c.prefix == 24)
    }

    @Test(arguments: ["", "300.1.1.1/24", "1.2.3/24", "1.2.3.4/33", "1.2.3.4/x", "a.b.c.d"])
    func rejectsInvalidInput(_ input: String) {
        #expect(SubnetCalculation(input) == nil)
    }

    @Test func prefixFromMask() {
        #expect(SubnetCalculation.prefix(fromMask: "255.255.255.0") == 24)
        #expect(SubnetCalculation.prefix(fromMask: "255.255.240.0") == 20)
        #expect(SubnetCalculation.prefix(fromMask: "0.0.0.0") == 0)
        #expect(SubnetCalculation.prefix(fromMask: "255.0.255.0") == nil)
    }
}

struct MagicPacketTests {

    @Test(arguments: ["AA:BB:CC:DD:EE:FF", "aa-bb-cc-dd-ee-ff", "AABBCCDDEEFF"])
    func parsesMACFormats(_ mac: String) {
        #expect(MagicPacket.macBytes(mac) == [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
    }

    @Test(arguments: ["AA:BB:CC:DD:EE", "AA:BB:CC:DD:EE:FF:00", "GG:BB:CC:DD:EE:FF"])
    func rejectsInvalidMAC(_ mac: String) {
        #expect(MagicPacket.macBytes(mac) == nil)
    }

    @Test func packetLayout() {
        let mac: [UInt8] = [1, 2, 3, 4, 5, 6]
        let packet = MagicPacket.packet(for: mac)
        #expect(packet.count == 102)
        #expect(Array(packet.prefix(6)) == [UInt8](repeating: 0xFF, count: 6))
        #expect(Array(packet[6..<12]) == mac)
        #expect(Array(packet.suffix(6)) == mac)
    }
}
