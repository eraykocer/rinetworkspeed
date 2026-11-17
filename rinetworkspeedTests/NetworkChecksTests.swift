//
//  NetworkChecksTests.swift
//  rinetworkspeedTests
//
//  Pure logic of the 4.8–4.14 tools: camera evidence, Wi-Fi safety, DNS
//  packets and ranking, STUN and NAT, streaming and gaming ratings, time of
//  day analysis and cellular context.
//

import Foundation
import Testing
import CoreTelephony
@testable import rinetworkspeed

struct CameraEvidenceTests {

    @Test func videoPortMakesALikelyCamera() throws {
        let suspect = try #require(CameraEvidence.assess(address: "192.168.1.30", openPorts: [554], identity: nil, answeredONVIF: false))
        #expect(suspect.level == .likely)
        #expect(suspect.reasons == [.videoStream(554)])
    }

    @Test func makerPortAloneIsOnlyPossible() throws {
        let suspect = try #require(CameraEvidence.assess(address: "192.168.1.31", openPorts: [8000], identity: nil, answeredONVIF: false))
        #expect(suspect.level == .possible)
        #expect(suspect.reasons == [.makerPort(8000, maker: "Hikvision")])
    }

    @Test func announcementsAndMakers() throws {
        var identity = DeviceIdentity()
        identity.manufacturer = "EZVIZ"
        identity.kind = .camera
        let suspect = try #require(CameraEvidence.assess(address: "192.168.1.32", openPorts: [], identity: identity, answeredONVIF: true))
        #expect(suspect.level == .likely)
        #expect(suspect.reasons == [.onvif, .announcedAsCamera, .cameraMaker("ezviz")])
    }

    @Test func ordinaryDeviceIsNotASuspect() {
        var identity = DeviceIdentity()
        identity.model = "iPhone15,2"
        #expect(CameraEvidence.assess(address: "192.168.1.5", openPorts: [62078], identity: identity, answeredONVIF: false) == nil)
    }

    @Test func onvifMatching() {
        #expect(CameraEvidence.onvifProbe().contains("dn:NetworkVideoTransmitter"))
        #expect(CameraEvidence.isONVIFMatch("<d:ProbeMatches><d:ProbeMatch><d:Types>dn:NetworkVideoTransmitter</d:Types>"))
        #expect(!CameraEvidence.isONVIFMatch("<d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types>"))
    }
}

struct WiFiSafetyTests {

    @Test func publicRoots() {
        #expect(TLSRoots.isPublic(rootName: "GTS Root R1"))
        #expect(TLSRoots.isPublic(rootName: "ISRG Root X1"))
        #expect(TLSRoots.isPublic(rootName: "DigiCert Global Root G2"))
        #expect(!TLSRoots.isPublic(rootName: "Fortinet CA"))
        #expect(!TLSRoots.isPublic(rootName: "Acme Corp Inspection Root"))
    }

    @Test func lookAlikeNetworks() {
        var known = KnownWiFi()
        #expect(known.compare(gateway: "192.168.1.1", accessPoint: "aa:bb:cc:dd:ee:01") == .firstVisit)
        known.record(gateway: "192.168.1.1", accessPoint: "AA:BB:CC:DD:EE:01")
        #expect(known.compare(gateway: "192.168.1.1", accessPoint: "aa:bb:cc:dd:ee:01") == .same)
        #expect(known.compare(gateway: "192.168.1.1", accessPoint: "aa:bb:cc:dd:ee:02") == .newAccessPoint)
        #expect(known.compare(gateway: "10.0.0.1", accessPoint: "aa:bb:cc:dd:ee:01") == .differentRouter)
        #expect(known.compare(gateway: nil, accessPoint: nil) == .same)
    }
}

struct DNSBenchmarkTests {

    @Test func queryLayout() throws {
        let packet = try #require(DNSWire.query(id: 0xBEEF, name: "apple.com"))
        #expect(Array(packet[0...3]) == [0xBE, 0xEF, 0x01, 0x00])
        #expect(Array(packet[12...]) == [5] + Array("apple".utf8) + [3] + Array("com".utf8) + [0, 0, 1, 0, 1])
        #expect(DNSWire.query(id: 1, name: "a..b") != nil) // empty labels are skipped by split
        #expect(DNSWire.query(id: 1, name: String(repeating: "x", count: 64) + ".com") == nil)
    }

    @Test func responseParsing() {
        let answer: [UInt8] = [0xBE, 0xEF, 0x81, 0x80, 0, 1, 0, 2, 0, 0, 0, 0]
        let parsed = DNSWire.parse(answer, id: 0xBEEF)
        #expect(parsed?.responseCode == 0)
        #expect(parsed?.answers == 2)
        #expect(DNSWire.parse(answer, id: 0x1234) == nil)
        #expect(DNSWire.parse([0xBE, 0xEF, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0], id: 0xBEEF) == nil)
        let nxdomain: [UInt8] = [0xBE, 0xEF, 0x81, 0x83, 0, 1, 0, 0, 0, 0, 0, 0]
        #expect(DNSWire.parse(nxdomain, id: 0xBEEF)?.responseCode == 3)
    }

    @Test func rankingPrefersReliablePublicResolvers() throws {
        let providers = DNSProvider.publicProviders
        let fastButFlaky = DNSBenchmarkResult(provider: providers[0], samples: [5, nil, nil, 5])
        let steady = DNSBenchmarkResult(provider: providers[1], samples: [20, 22, 24, 21])
        let router = DNSBenchmarkResult(provider: .router("192.168.1.1"), samples: [2, 2, 2, 2])
        #expect(steady.median == 21.5)
        #expect(fastButFlaky.successShare == 0.5)
        let best = try #require(DNSBenchmarkResult.bestPublic([fastButFlaky, steady, router]))
        #expect(best.provider.id == "google")
    }
}

struct NATTests {
    private let transaction: [UInt8] = Array(1...12)

    @Test func bindingRequest() {
        let request = STUN.bindingRequest(transactionID: transaction)
        #expect(request.count == 20)
        #expect(Array(request[0...7]) == [0x00, 0x01, 0x00, 0x00, 0x21, 0x12, 0xA4, 0x42])
        #expect(Array(request[8...]) == transaction)
    }

    @Test func xorMappedAddress() throws {
        // 203.0.113.5:54321 XORed with the magic cookie.
        let port = UInt16(54321) ^ 0x2112
        let address: [UInt8] = [203 ^ 0x21, 0 ^ 0x12, 113 ^ 0xA4, 5 ^ 0x42]
        let attribute: [UInt8] = [0x00, 0x20, 0x00, 0x08, 0x00, 0x01, UInt8(port >> 8), UInt8(port & 0xFF)] + address
        let response: [UInt8] = [0x01, 0x01, 0x00, UInt8(attribute.count), 0x21, 0x12, 0xA4, 0x42] + transaction + attribute
        let mapped = try #require(STUN.parseMappedAddress(response, transactionID: transaction))
        #expect(mapped.address == "203.0.113.5")
        #expect(mapped.port == 54321)
        #expect(STUN.parseMappedAddress(response, transactionID: Array(repeating: 0, count: 12)) == nil)
    }

    @Test func plainMappedAddress() throws {
        let attribute: [UInt8] = [0x00, 0x01, 0x00, 0x08, 0x00, 0x01, 0x1F, 0x90, 198, 51, 100, 7]
        let response: [UInt8] = [0x01, 0x01, 0x00, UInt8(attribute.count), 0x21, 0x12, 0xA4, 0x42] + transaction + attribute
        let mapped = try #require(STUN.parseMappedAddress(response, transactionID: transaction))
        #expect(mapped.address == "198.51.100.7")
        #expect(mapped.port == 8080)
    }

    @Test func mappingBehaviour() {
        let a = (address: "203.0.113.5", port: UInt16(50000))
        let b = (address: "203.0.113.5", port: UInt16(50001))
        #expect(NATAnalysis.mapping([a, a]) == .endpointIndependent)
        #expect(NATAnalysis.mapping([a, b]) == .endpointDependent)
        #expect(NATAnalysis.mapping([a, nil]) == .unknown)
        #expect(NATAnalysis.mapping([nil, nil]) == .blocked)
    }

    @Test func natLayers() {
        #expect(NATAnalysis.layers(routerWAN: "100.70.1.2", publicAddress: "85.1.1.1", earlyHops: []) == .carrierGradeNAT)
        #expect(NATAnalysis.layers(routerWAN: "192.168.0.10", publicAddress: "85.1.1.1", earlyHops: []) == .doubleNAT)
        #expect(NATAnalysis.layers(routerWAN: "85.1.1.1", publicAddress: "85.1.1.1", earlyHops: []) == .publicAddress)
        #expect(NATAnalysis.layers(routerWAN: "85.1.1.1", publicAddress: "85.9.9.9", earlyHops: []) == .carrierGradeNAT)
        #expect(NATAnalysis.layers(routerWAN: nil, publicAddress: nil, earlyHops: ["100.64.0.1", "85.1.1.1"]) == .carrierGradeNAT)
        #expect(NATAnalysis.layers(routerWAN: nil, publicAddress: nil, earlyHops: ["192.168.0.1", "85.1.1.1"]) == .doubleNAT)
        #expect(NATAnalysis.layers(routerWAN: nil, publicAddress: nil, earlyHops: ["85.1.1.1"]) == .publicAddress)
        #expect(NATAnalysis.layers(routerWAN: nil, publicAddress: nil, earlyHops: []) == .unknown)
    }
}

struct ExperienceTests {

    @Test func videoVerdicts() {
        #expect(VideoTestResult(startupSeconds: 1.2, stalls: 0, highestHeight: 1080, observedMbps: 20).verdict == .smooth)
        #expect(VideoTestResult(startupSeconds: 4, stalls: 0, highestHeight: 1080, observedMbps: 20).verdict == .someBuffering)
        #expect(VideoTestResult(startupSeconds: 1, stalls: 1, highestHeight: 720, observedMbps: 8).verdict == .someBuffering)
        #expect(VideoTestResult(startupSeconds: 1, stalls: 3, highestHeight: 720, observedMbps: 8).verdict == .poor)
        #expect(VideoTestResult(startupSeconds: 1, stalls: 0, highestHeight: 360, observedMbps: 1).verdict == .poor)
        #expect(VideoTestResult(startupSeconds: nil, stalls: 0, highestHeight: 0, observedMbps: nil).verdict == .failed)
        #expect(VideoTestResult(startupSeconds: 1, stalls: 0, highestHeight: 1080, observedMbps: nil).qualityLabel == "1080p")
    }

    @Test func gamingRatings() {
        #expect(GamingLatency.rating(milliseconds: 25) == .great)
        #expect(GamingLatency.rating(milliseconds: 40) == .good)
        #expect(GamingLatency.rating(milliseconds: 90) == .playable)
        #expect(GamingLatency.rating(milliseconds: 150) == .poor)
    }
}

struct PeakHourTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(hour: Int, day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func dayParts() {
        #expect(DayPart(hour: 0) == .night)
        #expect(DayPart(hour: 6) == .morning)
        #expect(DayPart(hour: 13) == .afternoon)
        #expect(DayPart(hour: 23) == .evening)
    }

    @Test func eveningDropIsFound() throws {
        let samples: [(date: Date, downloadMbps: Double)] = [
            (at(hour: 9), 100), (at(hour: 10, day: 2), 96), (at(hour: 8, day: 3), 104),
            (at(hour: 21), 50), (at(hour: 20, day: 2), 55), (at(hour: 22, day: 3), 60),
            (at(hour: 14), 90)
        ]
        let analysis = PeakHourAnalysis(samples: samples, calendar: calendar)
        #expect(analysis.parts.map(\.part) == [.morning, .afternoon, .evening])
        let finding = try #require(analysis.finding)
        #expect(finding.slowest == .evening)
        #expect(finding.fastest == .morning)
        #expect(abs(finding.drop - 0.45) < 0.0001)
        #expect(finding.slowestCount == 3)
    }

    @Test func smallGapsAndFewTestsAreIgnored() {
        let even: [(date: Date, downloadMbps: Double)] = [
            (at(hour: 9), 100), (at(hour: 10), 100), (at(hour: 11), 100),
            (at(hour: 20), 80), (at(hour: 21), 80), (at(hour: 22), 80)
        ]
        #expect(PeakHourAnalysis(samples: even, calendar: calendar).finding == nil)

        let few: [(date: Date, downloadMbps: Double)] = [(at(hour: 9), 100), (at(hour: 21), 10)]
        #expect(PeakHourAnalysis(samples: few, calendar: calendar).finding == nil)
    }
}

@MainActor
struct CellularContextTests {

    @Test func radioLabels() {
        #expect(RadioTechnology.label(CTRadioAccessTechnologyNR) == "5G")
        #expect(RadioTechnology.label(CTRadioAccessTechnologyNRNSA) == "5G NSA")
        #expect(RadioTechnology.label(CTRadioAccessTechnologyLTE) == "4G")
        #expect(RadioTechnology.label(CTRadioAccessTechnologyHSDPA) == "3G")
        #expect(RadioTechnology.label(CTRadioAccessTechnologyEdge) == "2G")
        #expect(RadioTechnology.label("unknown") == nil)
    }

    @Test func roundingAndLevels() {
        #expect(ApproximateLocation.rounded(41.012345) == 41.012)
        #expect(ApproximateLocation.rounded(28.97861) == 28.979)
        #expect(CoverageLevel(downloadMbps: 120) == .fast)
        #expect(CoverageLevel(downloadMbps: 20) == .usable)
        #expect(CoverageLevel(downloadMbps: 3) == .slow)
    }

    @Test func newFieldsRoundTrip() throws {
        let result = SpeedTestResult(date: Date(timeIntervalSinceReferenceDate: 0), downloadSpeed: 1, uploadSpeed: 1, ping: 10,
                                     connection: .cellular, radioTechnology: "5G", latitude: 41.012, longitude: 28.979)
        let decoded = try JSONDecoder().decode(SpeedTestResult.self, from: JSONEncoder().encode(result))
        #expect(decoded.radioTechnology == "5G")
        #expect(decoded.latitude == 41.012)
        #expect(decoded.longitude == 28.979)
    }
}
