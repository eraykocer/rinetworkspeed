//
//  WiFiSignal.swift
//  rinetworkspeed
//
//  Real Wi-Fi signal values through a Shortcuts bridge. iOS gives apps no
//  RSSI API, but the Shortcuts action "Get Network Details" returns RSSI,
//  noise, channel, Wi-Fi standard and link rates. The user installs a small
//  shortcut once; the app runs it, and the shortcut opens
//  rinetworkspeed://wifi-signal?rssi=…&noise=… to hand the values back.
//

import Foundation
import Combine
import UIKit

// MARK: - Reading

nonisolated struct WiFiSignalReading: Codable, Equatable, Sendable {
    var date: Date
    /// Received signal strength, dBm (for example -55).
    var rssi: Int?
    /// Noise floor, dBm (for example -92).
    var noise: Int?
    var channel: Int?
    /// As Shortcuts reports it, for example "802.11ax".
    var standard: String?
    /// Link rates, Mbps.
    var txRate: Double?
    var rxRate: Double?
    var bssid: String?

    /// Signal-to-noise ratio, dB.
    var snr: Int? {
        guard let rssi, let noise else { return nil }
        return rssi - noise
    }

    var band: WiFiBand? {
        channel.flatMap(WiFiBand.init(channel:))
    }

    static let urlHost = "wifi-signal"

    /// Reads `rinetworkspeed://wifi-signal?rssi=-55&noise=-92&channel=36&standard=802.11ax&tx=866&rx=866&bssid=…`.
    /// Nil unless the URL is that link and carries an RSSI value.
    init?(url: URL, date: Date = Date()) {
        guard url.scheme == "rinetworkspeed",
              url.host()?.lowercased() == Self.urlHost,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }

        var values: [String: String] = [:]
        for item in items {
            if let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                values[item.name.lowercased()] = value
            }
        }
        guard let rssi = values["rssi"].flatMap(Self.number).map({ Int($0.rounded()) }), rssi < 0 else { return nil }

        self.date = date
        self.rssi = rssi
        // Some devices report a noise of 0 when they don't know it.
        self.noise = values["noise"].flatMap(Self.number).map { Int($0.rounded()) }.flatMap { $0 < 0 ? $0 : nil }
        self.channel = values["channel"].flatMap(Self.number).map { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
        self.standard = values["standard"]
        self.txRate = values["tx"].flatMap(Self.number).flatMap { $0 > 0 ? $0 : nil }
        self.rxRate = values["rx"].flatMap(Self.number).flatMap { $0 > 0 ? $0 : nil }
        self.bssid = values["bssid"]
    }

    /// Lenient number parsing: Shortcuts may add units ("-55 dBm") or use a
    /// decimal comma in some languages ("866,7").
    static func number(_ text: String) -> Double? {
        let kept = text.filter { "-0123456789.,".contains($0) }.replacingOccurrences(of: ",", with: ".")
        return Double(kept)
    }
}

// MARK: - Band and quality

nonisolated enum WiFiBand: Equatable, Sendable {
    case ghz2_4
    case ghz5
    case ghz6

    /// Best guess from the channel number. 6 GHz reuses some numbers of the
    /// other bands (1, 5, 9, 13 and 149–177), so those are taken as the far
    /// more common 2.4 GHz and 5 GHz.
    init?(channel: Int) {
        switch channel {
        case 1...14: self = .ghz2_4
        case 32...177: self = .ghz5
        case 15...31, 178...233: self = .ghz6
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .ghz2_4: return "2.4 GHz"
        case .ghz5: return "5 GHz"
        case .ghz6: return "6 GHz"
        }
    }
}

nonisolated enum SignalQuality: Equatable, Sendable {
    case excellent
    case good
    case fair
    case weak

    /// Common rule of thumb: above -50 dBm excellent, down to -60 good,
    /// down to -70 fair, weaker than that unreliable.
    init(rssi: Int) {
        switch rssi {
        case (-50)...: self = .excellent
        case (-60)...: self = .good
        case (-70)...: self = .fair
        default: self = .weak
        }
    }

    /// 40 dB and more excellent, 25 good, 15 fair, below that poor.
    init(snr: Int) {
        switch snr {
        case 40...: self = .excellent
        case 25...: self = .good
        case 15...: self = .fair
        default: self = .weak
        }
    }
}

// MARK: - Store and bridge

@MainActor
final class WiFiSignalStore: ObservableObject {
    static let shared = WiFiSignalStore()

    /// Must match the shortcut's name exactly.
    static let shortcutName = "RiNetwork Wi-Fi Signal"
    /// iCloud link of the ready-made shortcut; nil until one is published.
    static let shortcutShareURL: URL? = nil
    /// What the shortcut's "Open URLs" action opens, with the details as variables.
    static let callbackTemplate = "rinetworkspeed://wifi-signal?rssi=[RSSI]&noise=[Noise]&channel=[Channel Number]&standard=[Wi-Fi Standard]&tx=[TX Rate]&rx=[RX Rate]&bssid=[BSSID]"

    /// Newest first.
    @Published private(set) var readings: [WiFiSignalReading] = []
    /// True between running the shortcut and its answer.
    @Published private(set) var isWaiting = false

    var latest: WiFiSignalReading? { readings.first }

    /// The access point of the latest reading differs from the one before it,
    /// taken within the last hour (mesh or roaming between access points).
    var accessPointChanged: Bool {
        guard readings.count >= 2,
              let current = readings[0].bssid, let previous = readings[1].bssid,
              readings[0].date.timeIntervalSince(readings[1].date) < 3_600 else { return false }
        return current.lowercased() != previous.lowercased()
    }

    private let defaultsKey = "wifiSignalReadings"
    private let maxReadings = 50
    private var waitingTimeout: Task<Void, Never>?

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let stored = try? JSONDecoder().decode([WiFiSignalReading].self, from: data) {
            readings = stored
        }
    }

    /// Runs the shortcut; its answer arrives through `receive(_:)`.
    func requestReading() {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: Self.shortcutName)]
        guard let url = components.url else { return }

        isWaiting = true
        waitingTimeout?.cancel()
        waitingTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.isWaiting = false
        }
        UIApplication.shared.open(url)
    }

    func receive(_ reading: WiFiSignalReading) {
        waitingTimeout?.cancel()
        isWaiting = false
        readings.insert(reading, at: 0)
        if readings.count > maxReadings {
            readings.removeLast(readings.count - maxReadings)
        }
        if let data = try? JSONEncoder().encode(readings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
