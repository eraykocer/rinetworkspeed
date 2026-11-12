//
//  ToolReport.swift
//  rinetworkspeed
//
//  Plain-text summaries of tool results, shared from a toolbar button. The
//  system share sheet also offers Copy, so this covers both sharing and copying.
//

import SwiftUI

/// Toolbar share button that observes its source, so only the button
/// re-renders while a tool is updating.
struct ToolReportButton<Source: ObservableObject>: View {
    @ObservedObject var source: Source
    let report: (Source) -> String?

    var body: some View {
        if let text = report(source), !text.isEmpty {
            ShareLink(item: text) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel(Text("Share Results"))
        }
    }
}

extension View {
    /// Adds a share button for a tool's results to the navigation bar.
    func toolReport<Source: ObservableObject>(_ source: Source, _ report: @escaping (Source) -> String?) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ToolReportButton(source: source, report: report)
            }
        }
    }
}

/// Shared layout: title, the lines, then a footer with app name and time.
enum ToolReportFormat {
    static func make(title: String, lines: [String]) -> String {
        let footer = "— RiNetwork, " + Date().formatted(date: .abbreviated, time: .shortened)
        return ([title, ""] + lines + ["", footer]).joined(separator: "\n")
    }

    static func ms(_ value: Double) -> String { value.fixed(0) + " ms" }
}

// MARK: - Builders

extension IPScannerViewModel {
    var reportText: String? {
        guard !isScanning, !discoveredDevices.isEmpty else { return nil }
        let lines = discoveredDevices.map { device in
            [device.ip, device.hostname, ToolReportFormat.ms(device.responseTime), isNew(device) ? String(localized: "New") : nil]
                .compactMap { $0 }
                .joined(separator: "  ")
        }
        return ToolReportFormat.make(title: String(localized: "IP Scanner — \(subnetBase).0/24"), lines: lines)
    }
}

extension NetworkMapManager {
    var reportText: String? {
        guard !isScanning, !devices.isEmpty else { return nil }
        let lines = devices.map { device in
            [device.ip, device.hostname, device.deviceType.displayName, ToolReportFormat.ms(device.responseTime)]
                .compactMap { $0 }
                .joined(separator: "  ")
        }
        return ToolReportFormat.make(title: String(localized: "Network Map"), lines: lines)
    }
}

extension TracerouteViewModel {
    var reportText: String? {
        guard !isRunning, !hops.isEmpty else { return nil }
        let lines = hops.map { hop in
            let latency = hop.latency.map(ToolReportFormat.ms) ?? "* * *"
            return ["\(hop.hopNumber)", hop.ip, hop.hostname, latency].compactMap { $0 }.joined(separator: "  ")
        }
        return ToolReportFormat.make(title: String(localized: "Traceroute to \(targetHost)"), lines: lines)
    }
}

extension PortScannerViewModel {
    var reportText: String? {
        guard !isScanning, !results.isEmpty else { return nil }
        let open = results.filter(\.isOpen)
        let lines = open.isEmpty
            ? [String(localized: "No open ports found")]
            : open.map { "\($0.port)  \($0.serviceName)  \(ToolReportFormat.ms($0.responseTime))" }
        return ToolReportFormat.make(
            title: String(localized: "Open ports on \(targetHost) (\(portRangeText))"),
            lines: lines
        )
    }
}

extension DNSLookupViewModel {
    var reportText: String? {
        guard !isLoading, !records.isEmpty else { return nil }
        let lines = records.map { record in
            [record.type, record.value, record.ttl.map { "TTL \($0)" }].compactMap { $0 }.joined(separator: "  ")
        }
        return ToolReportFormat.make(title: String(localized: "DNS records for \(domain)"), lines: lines)
    }
}

extension SSLCheckerViewModel {
    var reportText: String? {
        guard !isLoading, let info = certInfo else { return nil }
        var lines = [
            String(localized: "Subject: \(info.subjectSummary)"),
            String(localized: "Issuer: \(info.issuerName)")
        ]
        if let from = info.notBefore {
            lines.append(String(localized: "Valid from: \(from.formatted(date: .abbreviated, time: .omitted))"))
        }
        if let until = info.notAfter {
            lines.append(String(localized: "Expires: \(until.formatted(date: .abbreviated, time: .omitted)) (\(info.statusLabel))"))
        }
        lines.append(String(localized: "SHA-256: \(info.sha256Fingerprint)"))
        if !info.chain.isEmpty {
            lines.append(String(localized: "Chain: \(info.chain.joined(separator: " → "))"))
        }
        return ToolReportFormat.make(title: String(localized: "SSL certificate for \(hostname)"), lines: lines)
    }
}

extension WhoisViewModel {
    var reportText: String? {
        guard !isLoading, let data else { return nil }
        let fields: [(String, String?)] = [
            (String(localized: "Registrar"), data.registrar),
            (String(localized: "Registered"), data.createdDate),
            (String(localized: "Updated"), data.updatedDate),
            (String(localized: "Expires"), data.expirationDate),
            (String(localized: "Domain Age"), data.domainAge),
            (String(localized: "Organization"), data.registrantOrg),
            (String(localized: "Country"), data.registrantCountry),
            (String(localized: "Name Servers"), data.nameServers.isEmpty ? nil : data.nameServers.joined(separator: ", ")),
            (String(localized: "Status"), data.status.isEmpty ? nil : data.status.joined(separator: ", "))
        ]
        let lines = fields.compactMap { label, value in value.map { "\(label): \($0)" } }
        return ToolReportFormat.make(title: "Whois — \(data.domainName)", lines: lines)
    }
}

extension PingMonitor {
    var reportText: String? {
        guard packetsSent > 0 else { return nil }
        let lines = [
            String(localized: "Sent: \(packetsSent), lost: \(packetsLost) (\(packetLossPercent.fixed(0))%)"),
            String(localized: "Min / avg / max: \(minPing.fixed(0)) / \(avgPing.fixed(0)) / \(maxPing.fixed(0)) ms"),
            String(localized: "Jitter: \(jitter.fixed(1)) ms")
        ]
        return ToolReportFormat.make(title: String(localized: "Ping to \(activeHost())"), lines: lines)
    }
}

extension TroubleshooterViewModel {
    var reportText: String? {
        guard !isRunning, let diagnosis else { return nil }
        var lines = [String(localized: diagnosis.title), diagnosis.advice, ""]
        lines += steps.map { step in
            let mark: String
            switch step.status {
            case .passed: mark = "✓"
            case .warning: mark = "!"
            case .failed: mark = "✗"
            default: mark = "–"
            }
            return "\(mark) \(String(localized: step.kind.title))" + (step.detail.map { ": \($0)" } ?? "")
        }
        return ToolReportFormat.make(title: String(localized: "Connection Troubleshooter"), lines: lines)
    }
}

extension WiFiSurveyStore {
    func reportText(for surveyID: UUID) -> String? {
        guard let survey = survey(id: surveyID), !survey.testedRooms.isEmpty else { return nil }
        let lines = survey.testedRooms
            .sorted { ($0.download ?? 0) > ($1.download ?? 0) }
            .map { room in
                "\(room.name): ↓ \((room.downloadMbps ?? 0).fixed(1))  ↑ \((room.uploadMbps ?? 0).fixed(1)) Mbps, \((room.ping ?? 0).fixed(0)) ms"
            }
        return ToolReportFormat.make(title: String(localized: "Wi-Fi survey: \(survey.name)"), lines: lines)
    }
}
