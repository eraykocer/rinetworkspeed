//
//  ModemTests.swift
//  rinetworkspeedTests
//
//  SSDP responses, UPnP device descriptions and SOAP replies, and the plan /
//  line / test comparison.
//

import Foundation
import Testing
@testable import rinetworkspeed

struct SSDPTests {

    @Test func searchMessageFormat() {
        let message = SSDP.searchMessage(target: "urn:schemas-upnp-org:device:InternetGatewayDevice:1")
        #expect(message.hasPrefix("M-SEARCH * HTTP/1.1\r\n"))
        #expect(message.contains("MAN: \"ssdp:discover\"\r\n"))
        #expect(message.contains("ST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n"))
        #expect(message.hasSuffix("\r\n\r\n"))
    }

    @Test func parsesResponseWithAnyHeaderCase() throws {
        let text = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=120\r\nlocation: http://192.168.1.1:5431/dyndev/uuid:abc\r\nSt: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\nServer: Linux UPnP/1.0\r\n\r\n"
        let response = try #require(SSDP.parseResponse(text))
        #expect(response.location.absoluteString == "http://192.168.1.1:5431/dyndev/uuid:abc")
        #expect(response.searchTarget == "urn:schemas-upnp-org:device:InternetGatewayDevice:1")
        #expect(response.server == "Linux UPnP/1.0")
    }

    @Test func rejectsOtherMessages() {
        #expect(SSDP.parseResponse("NOTIFY * HTTP/1.1\r\nLOCATION: http://1.2.3.4/\r\n\r\n") == nil)
        #expect(SSDP.parseResponse("HTTP/1.1 200 OK\r\nST: x\r\n\r\n") == nil)
        #expect(SSDP.parseResponse("HTTP/1.1 200 OK\r\nLOCATION: ftp://1.2.3.4/\r\n\r\n") == nil)
    }
}

struct UPnPDescriptionTests {
    private let location = URL(string: "http://192.168.1.1:5000/rootDesc.xml")!

    private func description(urlBase: String? = nil) -> Data {
        let base = urlBase.map { "<URLBase>\($0)</URLBase>" } ?? ""
        return Data("""
        <?xml version="1.0"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          \(base)
          <device>
            <deviceType>urn:schemas-upnp-org:device:InternetGatewayDevice:1</deviceType>
            <friendlyName>Home Gateway</friendlyName>
            <manufacturer>ZTE</manufacturer>
            <modelName>H298A</modelName>
            <deviceList>
              <device>
                <friendlyName>WAN Device</friendlyName>
                <serviceList>
                  <service>
                    <serviceType>urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1</serviceType>
                    <controlURL>/ctl/CmnIfCfg</controlURL>
                  </service>
                </serviceList>
                <deviceList>
                  <device>
                    <serviceList>
                      <service>
                        <serviceType>urn:schemas-upnp-org:service:WANIPConnection:2</serviceType>
                        <controlURL>http://192.168.1.1:5000/ctl/IPConn</controlURL>
                      </service>
                    </serviceList>
                  </device>
                </deviceList>
              </device>
            </deviceList>
          </device>
        </root>
        """.utf8)
    }

    @Test func readsRootDeviceAndServices() throws {
        let parsed = try #require(UPnPDescription.parse(description(), location: location))
        #expect(parsed.friendlyName == "Home Gateway")
        #expect(parsed.manufacturer == "ZTE")
        #expect(parsed.modelName == "H298A")
        #expect(parsed.service(prefix: UPnPGateway.wanCommonService)?.controlURL.absoluteString == "http://192.168.1.1:5000/ctl/CmnIfCfg")
        #expect(parsed.service(prefix: UPnPGateway.wanIPService)?.controlURL.absoluteString == "http://192.168.1.1:5000/ctl/IPConn")
        #expect(parsed.service(prefix: UPnPGateway.wanPPPService) == nil)
    }

    @Test func controlURLsFollowURLBase() throws {
        let parsed = try #require(UPnPDescription.parse(description(urlBase: "http://192.168.1.1:49152/"), location: location))
        #expect(parsed.service(prefix: UPnPGateway.wanCommonService)?.controlURL.absoluteString == "http://192.168.1.1:49152/ctl/CmnIfCfg")
    }

    @Test func invalidXMLGivesNil() {
        #expect(UPnPDescription.parse(Data("<root><device>".utf8), location: location) == nil)
    }
}

struct UPnPSOAPTests {

    @Test func envelopeContainsActionAndArguments() {
        let envelope = UPnPSOAP.envelope(
            action: "GetGenericPortMappingEntry",
            service: "urn:schemas-upnp-org:service:WANIPConnection:1",
            arguments: [("NewPortMappingIndex", "3")]
        )
        #expect(envelope.contains("<u:GetGenericPortMappingEntry xmlns:u=\"urn:schemas-upnp-org:service:WANIPConnection:1\">"))
        #expect(envelope.contains("<NewPortMappingIndex>3</NewPortMappingIndex>"))
        #expect(envelope.contains("</s:Envelope>"))
    }

    @Test func parsesValuesByLocalName() throws {
        let response = Data("""
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
        <u:GetCommonLinkPropertiesResponse xmlns:u="urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1">
        <NewWANAccessType>DSL</NewWANAccessType>
        <NewLayer1UpstreamMaxBitRate>11500000</NewLayer1UpstreamMaxBitRate>
        <NewLayer1DownstreamMaxBitRate>52300000</NewLayer1DownstreamMaxBitRate>
        <NewPhysicalLinkStatus>Up</NewPhysicalLinkStatus>
        </u:GetCommonLinkPropertiesResponse></s:Body></s:Envelope>
        """.utf8)
        let values = try #require(UPnPSOAP.parseResponse(response))
        #expect(values["NewWANAccessType"] == "DSL")
        #expect(values["NewLayer1DownstreamMaxBitRate"] == "52300000")
        #expect(values["NewPhysicalLinkStatus"] == "Up")
    }

    @Test func faultGivesNil() {
        let fault = Data("""
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>
        <faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring>
        <detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>713</errorCode></UPnPError></detail>
        </s:Fault></s:Body></s:Envelope>
        """.utf8)
        #expect(UPnPSOAP.parseResponse(fault) == nil)
    }

    @Test func portMappingEntry() throws {
        let mapping = try #require(UPnPSOAP.portMapping(from: [
            "NewExternalPort": "51413", "NewProtocol": "TCP", "NewInternalClient": "192.168.1.20",
            "NewInternalPort": "51413", "NewEnabled": "1", "NewPortMappingDescription": "Transmission"
        ]))
        #expect(mapping.externalPort == 51413)
        #expect(mapping.transport == "TCP")
        #expect(mapping.internalClient == "192.168.1.20")
        #expect(mapping.enabled)
        #expect(mapping.description == "Transmission")

        #expect(UPnPSOAP.portMapping(from: ["NewProtocol": "UDP"]) == nil)
        let disabled = UPnPSOAP.portMapping(from: [
            "NewExternalPort": "1", "NewProtocol": "UDP", "NewInternalClient": "x", "NewInternalPort": "1",
            "NewEnabled": "0", "NewPortMappingDescription": ""
        ])
        #expect(disabled?.enabled == false)
        #expect(disabled?.description == nil)
    }
}

@MainActor
struct LineComparisonTests {

    @Test func lineBelowPlanWinsOverEverything() {
        #expect(LineComparison(lineMbps: 35, planMbps: 100, testMbps: 30).verdict == .lineBelowPlan)
        #expect(LineComparison(lineMbps: 35, planMbps: 100, testMbps: nil).verdict == .lineBelowPlan)
    }

    @Test func gapInsideTheHome() {
        #expect(LineComparison(lineMbps: 105, planMbps: 100, testMbps: 40).verdict == .homeBelowLine)
        #expect(LineComparison(lineMbps: 105, planMbps: nil, testMbps: 40).verdict == .homeBelowLine)
    }

    @Test func consistentAndMissingData() {
        #expect(LineComparison(lineMbps: 105, planMbps: 100, testMbps: 92).verdict == .consistent)
        #expect(LineComparison(lineMbps: 105, planMbps: nil, testMbps: 92).verdict == .needsPlan)
        #expect(LineComparison(lineMbps: 105, planMbps: 100, testMbps: nil).verdict == .needsTests)
    }

    @Test func limits() {
        // Exactly 90 % of the plan and exactly 70 % of the line are not below.
        #expect(LineComparison(lineMbps: 90, planMbps: 100, testMbps: 63).verdict == .consistent)
    }

    @Test func recentWiFiTestsOnly() throws {
        let now = Date()
        func result(_ mbps: Double, daysAgo: Double, _ kind: ConnectionKind) -> SpeedTestResult {
            SpeedTestResult(date: now.addingTimeInterval(-daysAgo * 86_400),
                            downloadSpeed: mbps * 1_000_000 / 8, uploadSpeed: 0, ping: 10, connection: kind)
        }
        let results = [
            result(50, daysAgo: 1, .wifi),
            result(70, daysAgo: 2, .wifi),
            result(60, daysAgo: 3, .wifi),
            result(300, daysAgo: 1, .cellular),
            result(10, daysAgo: 30, .wifi)
        ]
        let median = try #require(LineComparison.recentWiFiDownloadMbps(results, now: now))
        #expect(abs(median - 60) < 0.0001)
        #expect(LineComparison.recentWiFiDownloadMbps([result(5, daysAgo: 1, .cellular)], now: now) == nil)
    }
}

struct ModemReadingTests {

    @Test func onlyDSLIsALineRate() {
        var reading = ModemReading()
        reading.accessType = "DSL"
        #expect(reading.isLineRate)
        reading.accessType = "Ethernet"
        #expect(!reading.isLineRate)
        reading.accessType = nil
        #expect(!reading.isLineRate)
    }

    @Test func storeKeepsRecentDSLReadingsOnly() throws {
        let defaults = try #require(UserDefaults(suiteName: "ModemReadingTests-\(UUID().uuidString)"))
        var reading = ModemReading()
        reading.accessType = "DSL"
        reading.downstreamBitsPerSecond = 52_300_000
        ModemReadingStore.save(reading, to: defaults)

        #expect(ModemReadingStore.load(from: defaults)?.downstreamMbps == 52.3)
        #expect(ModemReadingStore.recentLineReading(from: defaults) != nil)
        #expect(ModemReadingStore.recentLineReading(from: defaults, now: Date().addingTimeInterval(61 * 86_400)) == nil)

        reading.accessType = "Ethernet"
        ModemReadingStore.save(reading, to: defaults)
        #expect(ModemReadingStore.recentLineReading(from: defaults) == nil)
    }
}
