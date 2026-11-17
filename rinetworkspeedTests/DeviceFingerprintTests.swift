//
//  DeviceFingerprintTests.swift
//  rinetworkspeedTests
//
//  MAC normalisation, kind guessing, Bonjour TXT records, NetBIOS node
//  status packets and web page titles.
//

import Testing
@testable import rinetworkspeed

struct DeviceIdentityTests {

    @Test func normalisesMACAddresses() {
        #expect(DeviceIdentity.normalizedMAC("a4:2b:b0:1:2:33") == "A4:2B:B0:01:02:33")
        #expect(DeviceIdentity.normalizedMAC("A42BB0010233") == "A4:2B:B0:01:02:33")
        #expect(DeviceIdentity.normalizedMAC("a4-2b-b0-01-02-33") == "A4:2B:B0:01:02:33")
        #expect(DeviceIdentity.normalizedMAC("00:00:00:00:00:00") == nil)
        #expect(DeviceIdentity.normalizedMAC("FF:FF:FF:FF:FF:FF") == nil)
        #expect(DeviceIdentity.normalizedMAC("not a mac") == nil)
    }

    @Test func privateMACIsRecognised() {
        var identity = DeviceIdentity()
        identity.mac = "A6:2B:B0:01:02:33" // second hex digit 6: locally administered
        #expect(identity.hasPrivateMAC)
        identity.mac = "A4:2B:B0:01:02:33"
        #expect(!identity.hasPrivateMAC)
    }

    @Test(arguments: [
        ("AppleTV11,1", DeviceKind.tv),
        ("AudioAccessory5,1", DeviceKind.speaker),
        ("iPhone15,2", DeviceKind.phone),
        ("iPad13,4", DeviceKind.tablet),
        ("MacBookPro18,1", DeviceKind.computer),
        ("HP LaserJet M15w", DeviceKind.printer),
        ("DS-2CD2143G2 Hikvision", DeviceKind.camera),
        ("DiskStation DS220+", DeviceKind.storage)
    ])
    func guessesKindFromModel(model: String, kind: DeviceKind) {
        var identity = DeviceIdentity()
        identity.model = model
        #expect(DeviceIdentity.guessKind(identity) == kind)
    }

    @Test func guessesKindFromHints() {
        var identity = DeviceIdentity()
        identity.hints = ["urn:schemas-upnp-org:device:InternetGatewayDevice:1"]
        #expect(DeviceIdentity.guessKind(identity) == .router)
        identity.hints = ["_hap._tcp.", "hap-category:17"]
        #expect(DeviceIdentity.guessKind(identity) == .camera)
        #expect(DeviceIdentity.guessKind(DeviceIdentity()) == nil)
    }

    @Test func mergeKeepsFirstValuesAndCollectsSources() {
        var first = DeviceIdentity()
        first.name = "Living Room"
        first.sources = ["_airplay._tcp"]
        var second = DeviceIdentity()
        second.name = "Other"
        second.model = "AppleTV11,1"
        second.mac = "A4:2B:B0:01:02:33"
        second.sources = ["NetBIOS"]
        first.merge(second)
        #expect(first.name == "Living Room")
        #expect(first.model == "AppleTV11,1")
        #expect(first.mac == "A4:2B:B0:01:02:33")
        #expect(first.sources == ["_airplay._tcp", "NetBIOS"])
        #expect(first.kind == .tv)
        #expect(first.detail == "AppleTV11,1")
    }
}

struct BonjourFingerprintTests {

    @Test func airPlay() {
        let identity = BonjourFingerprint.identity(serviceName: "Living Room", type: "_airplay._tcp",
                                                   txt: ["model": "AppleTV11,1", "deviceid": "a4:2b:b0:01:02:33"])
        #expect(identity.name == "Living Room")
        #expect(identity.model == "AppleTV11,1")
        #expect(identity.manufacturer == "Apple")
        #expect(identity.mac == "A4:2B:B0:01:02:33")
        #expect(identity.kind == .tv)
    }

    @Test func raopNameCarriesTheMAC() {
        let identity = BonjourFingerprint.identity(serviceName: "A42BB0010233@Kitchen", type: "_raop._tcp",
                                                   txt: ["am": "AudioAccessory5,1"])
        #expect(identity.name == "Kitchen")
        #expect(identity.mac == "A4:2B:B0:01:02:33")
        #expect(identity.kind == .speaker)
    }

    @Test func googleCast() {
        let identity = BonjourFingerprint.identity(serviceName: "Chromecast-abc123", type: "_googlecast._tcp",
                                                   txt: ["fn": "Bedroom TV", "md": "Chromecast"])
        #expect(identity.name == "Bedroom TV")
        #expect(identity.model == "Chromecast")
        #expect(identity.kind == .tv)
    }

    @Test func printer() {
        let identity = BonjourFingerprint.identity(serviceName: "HP LaserJet M15w", type: "_ipp._tcp",
                                                   txt: ["ty": "HP LaserJet M15w", "usb_MFG": "HP"])
        #expect(identity.model == "HP LaserJet M15w")
        #expect(identity.manufacturer == "HP")
        #expect(identity.kind == .printer)
    }

    @Test func workstationNameCarriesTheMAC() {
        let identity = BonjourFingerprint.identity(serviceName: "nas [00:11:32:aa:bb:cc]", type: "_workstation._tcp", txt: [:])
        #expect(identity.name == "nas")
        #expect(identity.mac == "00:11:32:AA:BB:CC")
    }
}

struct NetBIOSFingerprintTests {

    @Test func requestLayout() {
        let packet = NetBIOSFingerprint.nodeStatusRequest(transactionID: 0x1234)
        #expect(packet.count == 50)
        #expect(Array(packet[0...1]) == [0x12, 0x34])
        #expect(packet[12] == 0x20)
        // "*" (0x2A) encodes as "CK", the zero padding as "AA".
        #expect(Array(packet[13...16]) == Array("CKAA".utf8))
        #expect(packet[45] == 0x00)
        #expect(Array(packet[46...49]) == [0x00, 0x21, 0x00, 0x01])
    }

    private func entry(_ name: String, group: Bool) -> [UInt8] {
        var bytes = Array(name.utf8) + [UInt8](repeating: 0x20, count: 15 - name.utf8.count)
        bytes.append(0x00)
        bytes += [group ? 0x84 : 0x04, 0x00]
        return bytes
    }

    @Test func parsesNameWorkgroupAndMAC() throws {
        var response: [UInt8] = [0x12, 0x34, 0x84, 0x00, 0, 0, 0, 1, 0, 0, 0, 0]
        response += [0x20] + Array(String(repeating: "A", count: 32).utf8) + [0x00]
        response += [0x00, 0x21, 0x00, 0x01, 0, 0, 0, 0, 0x00, 0x41]
        response += [2] + entry("ERAY-PC", group: false) + entry("WORKGROUP", group: true)
        response += [0xA4, 0x2B, 0xB0, 0x01, 0x02, 0x33] + [UInt8](repeating: 0, count: 10)

        let parsed = try #require(NetBIOSFingerprint.parse(response))
        #expect(parsed.name == "ERAY-PC")
        #expect(parsed.workgroup == "WORKGROUP")
        #expect(parsed.mac == "A4:2B:B0:01:02:33")
    }

    @Test func zeroMACAndQueriesAreIgnored() throws {
        var response: [UInt8] = [0x12, 0x34, 0x84, 0x00, 0, 0, 0, 1, 0, 0, 0, 0]
        response += [0xC0, 0x0C]
        response += [0x00, 0x21, 0x00, 0x01, 0, 0, 0, 0, 0x00, 0x17]
        response += [1] + entry("SAMBA", group: false) + [UInt8](repeating: 0, count: 6)
        let parsed = try #require(NetBIOSFingerprint.parse(response))
        #expect(parsed.name == "SAMBA")
        #expect(parsed.mac == nil)

        #expect(NetBIOSFingerprint.parse(NetBIOSFingerprint.nodeStatusRequest(transactionID: 1)) == nil)
        #expect(NetBIOSFingerprint.parse([0, 1, 0x84]) == nil)
    }
}

struct HTTPFingerprintTests {

    @Test func readsTheTitle() {
        #expect(HTTPFingerprint.title(in: "<html><head><TITLE>\n  Synology   DiskStation </TITLE></head>") == "Synology DiskStation")
        #expect(HTTPFingerprint.title(in: "<title lang=\"en\">Hikvision</title>") == "Hikvision")
        #expect(HTTPFingerprint.title(in: "<title></title>") == nil)
        #expect(HTTPFingerprint.title(in: "<html>no title</html>") == nil)
    }
}
