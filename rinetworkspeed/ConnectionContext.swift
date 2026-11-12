//
//  ConnectionContext.swift
//  rinetworkspeed
//
//  Describes the connection a speed test ran on, so history can be filtered
//  and compared per network: interface type, Wi-Fi name and provider.
//

import Foundation
import Network
import NetworkExtension

enum ConnectionKind: String, Codable, CaseIterable, Identifiable {
    case wifi
    case cellular
    case wired
    case other

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        case .wired: return "Wired"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .wired: return "cable.connector"
        case .other: return "network"
        }
    }
}

struct ConnectionContext: Sendable {
    let kind: ConnectionKind
    /// Only available with location permission.
    let ssid: String?
    /// Internet provider as reported by Cloudflare, the same service the test uses.
    let isp: String?

    nonisolated static func capture() async -> ConnectionContext {
        async let kind = currentKind()
        async let isp = fetchISP()

        let resolvedKind = await kind
        let ssid = resolvedKind == .wifi ? await NEHotspotNetwork.fetchCurrent()?.ssid : nil
        return ConnectionContext(kind: resolvedKind, ssid: ssid, isp: await isp)
    }

    nonisolated private static func currentKind() async -> ConnectionKind {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let once = OnceContinuation(continuation)
            monitor.pathUpdateHandler = { path in
                let kind: ConnectionKind
                if path.usesInterfaceType(.wifi) {
                    kind = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    kind = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    kind = .wired
                } else {
                    kind = .other
                }
                once.resume(kind)
                monitor.cancel()
            }
            monitor.start(queue: DispatchQueue(label: "rinetworkspeed.connection.context"))
        }
    }

    private struct CloudflareMeta: Decodable {
        let asOrganization: String?
    }

    nonisolated private static func fetchISP() async -> String? {
        guard let url = URL(string: "https://speed.cloudflare.com/meta") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        // The endpoint returns an empty object without the speed test page as referrer.
        request.setValue("https://speed.cloudflare.com/", forHTTPHeaderField: "Referer")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let meta = try? JSONDecoder().decode(CloudflareMeta.self, from: data),
              let name = meta.asOrganization, !name.isEmpty else {
            return nil
        }
        return name
    }
}

/// Resumes a continuation exactly once, whichever callback fires first.
nonisolated final class OnceContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
