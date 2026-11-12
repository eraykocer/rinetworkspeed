//
//  NetworkToolsView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI

// MARK: - Tool Model

private enum NetworkTool: String, CaseIterable, Identifiable, Hashable {
    case ipScanner
    case networkMap
    case traceroute
    case portScanner
    case dnsLookup
    case sslChecker
    case whois

    var id: String { rawValue }

    var name: LocalizedStringKey {
        switch self {
        case .ipScanner: "IP Scanner"
        case .networkMap: "Network Map"
        case .traceroute: "Traceroute"
        case .portScanner: "Port Scanner"
        case .dnsLookup: "DNS Lookup"
        case .sslChecker: "SSL Checker"
        case .whois: "Whois"
        }
    }

    var description: LocalizedStringKey {
        switch self {
        case .ipScanner: "Discover devices on local network"
        case .networkMap: "Visually discover devices on the local network"
        case .traceroute: "Hop-by-hop path analysis"
        case .portScanner: "Check open TCP ports on a host"
        case .dnsLookup: "Query DNS records for any domain"
        case .sslChecker: "Certificate validity & details"
        case .whois: "Domain registration information"
        }
    }

    /// Plain-text keywords used for search filtering.
    var searchTerms: String {
        switch self {
        case .ipScanner: "ip scanner devices lan local network"
        case .networkMap: "network map devices topology local"
        case .traceroute: "traceroute hops route path latency"
        case .portScanner: "port scanner tcp open ports host"
        case .dnsLookup: "dns lookup records domain a aaaa mx"
        case .sslChecker: "ssl tls certificate checker https"
        case .whois: "whois domain registration registrar"
        }
    }

    var icon: String {
        switch self {
        case .ipScanner: "network"
        case .networkMap: "circle.hexagongrid.fill"
        case .traceroute: "point.3.connected.trianglepath.dotted"
        case .portScanner: "door.left.hand.open"
        case .dnsLookup: "globe.americas.fill"
        case .sslChecker: "lock.shield.fill"
        case .whois: "doc.text.magnifyingglass"
        }
    }

    var tint: Color {
        switch self {
        case .ipScanner: Color(red: 0.24, green: 0.45, blue: 0.99)
        case .networkMap: Color(red: 0.20, green: 0.80, blue: 0.65)
        case .traceroute: Color(red: 0.13, green: 0.72, blue: 0.52)
        case .portScanner: Color(red: 0.84, green: 0.28, blue: 0.74)
        case .dnsLookup: Color(red: 0.98, green: 0.62, blue: 0.16)
        case .sslChecker: Color(red: 0.20, green: 0.75, blue: 0.99)
        case .whois: Color(red: 0.99, green: 0.37, blue: 0.37)
        }
    }
}

private enum NetworkToolSection: CaseIterable, Identifiable {
    case localNetwork
    case diagnostics
    case domainSecurity

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .localNetwork: "Local Network"
        case .diagnostics: "Diagnostics"
        case .domainSecurity: "Domain & Security"
        }
    }

    var tools: [NetworkTool] {
        switch self {
        case .localNetwork: [.ipScanner, .networkMap]
        case .diagnostics: [.traceroute, .portScanner]
        case .domainSecurity: [.dnsLookup, .sslChecker, .whois]
        }
    }
}

// MARK: - Main View

struct NetworkToolsView: View {
    /// Shared app-wide manager; only the hero card and SpeedTestView observe it,
    /// so live test updates don't invalidate the whole tools list.
    let speedTestManager: SpeedTestManager

    @State private var searchText = ""

    private let backgroundColor = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func filteredTools(in section: NetworkToolSection) -> [NetworkTool] {
        guard isSearching else { return section.tools }
        let query = searchText.lowercased()
        return section.tools.filter { $0.searchTerms.contains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    if !isSearching || "speed test download upload ping".contains(searchText.lowercased()) {
                        NavigationLink {
                            SpeedTestView(manager: speedTestManager)
                        } label: {
                            SpeedTestHeroCard(manager: speedTestManager)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }

                    ForEach(NetworkToolSection.allCases) { section in
                        let tools = filteredTools(in: section)
                        if !tools.isEmpty {
                            ToolSectionView(title: section.title, tools: tools)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Network Tools")
            .searchable(text: $searchText, prompt: Text("Search tools"))
            .navigationDestination(for: NetworkTool.self) { tool in
                destinationView(for: tool)
            }
        }
        .background(backgroundColor.ignoresSafeArea())
    }

    @ViewBuilder
    private func destinationView(for tool: NetworkTool) -> some View {
        switch tool {
        case .ipScanner: IPScannerView()
        case .networkMap: NetworkMapView()
        case .traceroute: TracerouteView()
        case .portScanner: PortScannerView()
        case .dnsLookup: DNSLookupView()
        case .sslChecker: SSLCheckerView()
        case .whois: WhoisView()
        }
    }
}

// MARK: - Speed Test Hero Card

private struct SpeedTestHeroCard: View {
    @ObservedObject var manager: SpeedTestManager

    private let gradient = [Color(red: 0.16, green: 0.47, blue: 0.96),
                            Color(red: 0.42, green: 0.22, blue: 0.93)]

    private var isRunning: Bool {
        switch manager.state {
        case .pingTesting, .downloadTesting, .transitionToUpload, .uploadTesting: true
        default: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Speed Test")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Measure ping, download and upload speed")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 12)

                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if let last = manager.history.first {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Last result · \(last.date, format: .relative(presentation: .named))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .textCase(.uppercase)

                    HStack(spacing: 0) {
                        metric(icon: "arrow.down", value: mbps(last.downloadSpeed), unit: "Mbps")
                        divider
                        metric(icon: "arrow.up", value: mbps(last.uploadSpeed), unit: "Mbps")
                        divider
                        metric(icon: "timer", value: String(format: "%.0f", last.ping), unit: "ms")
                    }
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            HStack(spacing: 8) {
                Image(systemName: isRunning ? "waveform" : "play.fill")
                    .symbolEffect(.variableColor.iterative, isActive: isRunning)
                Text(isRunning ? "Test in progress" : (manager.history.isEmpty ? "Start Test" : "Test Again"))
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(gradient[1])
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white, in: Capsule())
        }
        .padding(20)
        .background(
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: gradient[0].opacity(0.35), radius: 16, x: 0, y: 8)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.18))
            .frame(width: 1, height: 28)
    }

    private func metric(icon: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            Text(unit)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func mbps(_ bytesPerSecond: Double) -> String {
        String(format: "%.1f", bytesPerSecond * 8 / 1_000_000)
    }
}

// MARK: - Tool Section

private struct ToolSectionView: View {
    let title: LocalizedStringKey
    let tools: [NetworkTool]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(tools) { tool in
                    NavigationLink(value: tool) {
                        ToolRow(tool: tool)
                    }
                    .buttonStyle(RowButtonStyle())

                    if tool != tools.last {
                        Divider()
                            .overlay(.white.opacity(0.08))
                            .padding(.leading, 70)
                    }
                }
            }
            .background(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Tool Row

private struct ToolRow: View {
    let tool: NetworkTool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: tool.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(
                        colors: [tool.tint, tool.tint.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(tool.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(tool.description)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Button Styles

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.08) : Color.clear)
    }
}

#Preview {
    NetworkToolsView(speedTestManager: SpeedTestManager())
        .preferredColorScheme(.dark)
}
