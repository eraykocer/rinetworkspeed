//
//  WiFiSignalTests.swift
//  rinetworkspeedTests
//
//  The Shortcuts bridge URL, lenient number parsing, band and signal quality.
//

import Foundation
import Testing
@testable import rinetworkspeed

struct WiFiSignalReadingTests {

    @Test func readsAFullAnswer() throws {
        let url = try #require(URL(string: "rinetworkspeed://wifi-signal?rssi=-54&noise=-93&channel=36&standard=802.11ax&tx=864.6&rx=720&bssid=a4:2b:b0:11:22:33"))
        let reading = try #require(WiFiSignalReading(url: url))
        #expect(reading.rssi == -54)
        #expect(reading.noise == -93)
        #expect(reading.snr == 39)
        #expect(reading.channel == 36)
        #expect(reading.band == .ghz5)
        #expect(reading.standard == "802.11ax")
        #expect(reading.txRate == 864.6)
        #expect(reading.rxRate == 720)
        #expect(reading.bssid == "a4:2b:b0:11:22:33")
    }

    @Test func acceptsUnitsAndDecimalCommas() throws {
        let url = try #require(URL(string: "rinetworkspeed://WIFI-SIGNAL?RSSI=-61%20dBm&noise=-90&tx=866,7"))
        let reading = try #require(WiFiSignalReading(url: url))
        #expect(reading.rssi == -61)
        #expect(reading.txRate == 866.7)
        #expect(reading.channel == nil)
        #expect(reading.bssid == nil)
    }

    @Test func dropsUnknownValues() throws {
        let url = try #require(URL(string: "rinetworkspeed://wifi-signal?rssi=-70&noise=0&channel=0&tx=0&standard="))
        let reading = try #require(WiFiSignalReading(url: url))
        #expect(reading.noise == nil)
        #expect(reading.snr == nil)
        #expect(reading.channel == nil)
        #expect(reading.txRate == nil)
        #expect(reading.standard == nil)
    }

    @Test func rejectsOtherLinksAndMissingSignal() throws {
        #expect(WiFiSignalReading(url: try #require(URL(string: "rinetworkspeed://speedtest"))) == nil)
        #expect(WiFiSignalReading(url: try #require(URL(string: "rinetworkspeed://wifi-signal?noise=-90"))) == nil)
        #expect(WiFiSignalReading(url: try #require(URL(string: "rinetworkspeed://wifi-signal?rssi=%5BRSSI%5D"))) == nil)
        #expect(WiFiSignalReading(url: try #require(URL(string: "rinetworkspeed://wifi-signal?rssi=12"))) == nil)
        #expect(WiFiSignalReading(url: try #require(URL(string: "https://wifi-signal?rssi=-50"))) == nil)
    }

    @Test func lenientNumbers() {
        #expect(WiFiSignalReading.number("-55 dBm") == -55)
        #expect(WiFiSignalReading.number("866,7") == 866.7)
        #expect(WiFiSignalReading.number("abc") == nil)
    }
}

struct WiFiBandAndQualityTests {

    @Test(arguments: [(1, WiFiBand.ghz2_4), (11, WiFiBand.ghz2_4), (36, WiFiBand.ghz5),
                      (149, WiFiBand.ghz5), (177, WiFiBand.ghz5), (21, WiFiBand.ghz6), (229, WiFiBand.ghz6)])
    func bandFromChannel(channel: Int, band: WiFiBand) {
        #expect(WiFiBand(channel: channel) == band)
    }

    @Test func unknownChannel() {
        #expect(WiFiBand(channel: 0) == nil)
        #expect(WiFiBand(channel: 300) == nil)
    }

    @Test func signalQualityBands() {
        #expect(SignalQuality(rssi: -45) == .excellent)
        #expect(SignalQuality(rssi: -50) == .excellent)
        #expect(SignalQuality(rssi: -51) == .good)
        #expect(SignalQuality(rssi: -60) == .good)
        #expect(SignalQuality(rssi: -65) == .fair)
        #expect(SignalQuality(rssi: -71) == .weak)

        #expect(SignalQuality(snr: 45) == .excellent)
        #expect(SignalQuality(snr: 30) == .good)
        #expect(SignalQuality(snr: 20) == .fair)
        #expect(SignalQuality(snr: 10) == .weak)
    }
}
