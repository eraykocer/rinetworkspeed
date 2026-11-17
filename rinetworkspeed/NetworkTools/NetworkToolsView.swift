//
//  NetworkToolsView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Combine

// MARK: - Tool Model

private enum NetworkTool: String, CaseIterable, Identifiable, Hashable {
    case troubleshooter
    case modem
    case ipScanner
    case networkMap
    case wifiSurvey
    case wifiHeatmap
    case traceroute
    case portScanner
    case dnsLookup
    case sslChecker
    case whois
    case subnetCalculator
    case wakeOnLAN
    case cameraFinder
    case wifiSafety
    case dnsBenchmark
    case natType
    case experience

    var id: String { rawValue }

    /// The troubleshooter stays free; the other tools are part of Pro.
    var isFree: Bool { self == .troubleshooter }

    var name: LocalizedStringResource {
        switch self {
        case .troubleshooter: "Troubleshooter"
        case .modem: "Modem & Line"
        case .ipScanner: "IP Scanner"
        case .networkMap: "Network Map"
        case .wifiSurvey: "Wi-Fi Survey"
        case .wifiHeatmap: "Wi-Fi Heatmap"
        case .traceroute: "Traceroute"
        case .portScanner: "Port Scanner"
        case .dnsLookup: "DNS Lookup"
        case .sslChecker: "SSL Checker"
        case .whois: "Whois"
        case .subnetCalculator: "Subnet Calculator"
        case .wakeOnLAN: "Wake-on-LAN"
        case .cameraFinder: "Hidden Camera Check"
        case .wifiSafety: "Wi-Fi Safety"
        case .dnsBenchmark: "DNS Benchmark"
        case .natType: "NAT Type"
        case .experience: "Streaming & Gaming"
        }
    }

    var description: LocalizedStringResource {
        switch self {
        case .troubleshooter: "Find out why the internet isn't working"
        case .modem: "Line speed, internet address and open ports from your router"
        case .ipScanner: "Discover devices on local network"
        case .networkMap: "Visually discover devices on the local network"
        case .wifiSurvey: "Find the best and worst rooms for Wi-Fi"
        case .wifiHeatmap: "Map Wi-Fi quality across your floor plan"
        case .traceroute: "Hop-by-hop path analysis"
        case .portScanner: "Check open TCP ports on a host"
        case .dnsLookup: "Query DNS records for any domain"
        case .sslChecker: "Certificate validity & details"
        case .whois: "Domain registration information"
        case .subnetCalculator: "Network, broadcast and host range for any subnet"
        case .wakeOnLAN: "Turn on a computer over the network"
        case .cameraFinder: "Find cameras on the Wi-Fi of a rental or hotel"
        case .wifiSafety: "Is this Wi-Fi safe? Encryption, interception, fake networks"
        case .dnsBenchmark: "Find the fastest DNS and turn on encrypted DNS"
        case .natType: "Open, Moderate or Strict NAT, CGNAT and double NAT"
        case .experience: "Video playback test and latency to game server regions"
        }
    }

    /// English keywords plus the tool's name and description in the
    /// current language, so search works in any localization.
    var searchText: String {
        "\(keywords) \(String(localized: name)) \(String(localized: description))".lowercased()
    }

    /// Plain-text keywords used for search filtering.
    private var keywords: String {
        switch self {
        case .troubleshooter: "troubleshoot diagnose problem no internet router dns captive portal"
        case .modem: "modem router line sync rate vdsl dsl upnp wan ip cgnat nat port forwarding"
        case .ipScanner: "ip scanner devices lan local network"
        case .networkMap: "network map devices topology local"
        case .wifiSurvey: "wifi survey room coverage signal heatmap dead zone"
        case .wifiHeatmap: "wifi heatmap map floor plan coverage signal mesh router placement dead zone"
        case .traceroute: "traceroute hops route path latency"
        case .portScanner: "port scanner tcp open ports host"
        case .dnsLookup: "dns lookup records domain a aaaa mx"
        case .sslChecker: "ssl tls certificate checker https"
        case .whois: "whois domain registration registrar"
        case .subnetCalculator: "subnet calculator cidr mask netmask broadcast ip range"
        case .wakeOnLAN: "wake on lan wol magic packet power computer"
        case .cameraFinder: "hidden camera spy airbnb hotel rental rtsp onvif cctv"
        case .wifiSafety: "wifi safety secure public hotspot mitm interception evil twin dns hijack"
        case .dnsBenchmark: "dns benchmark fastest resolver doh encrypted cloudflare google quad9 adguard"
        case .natType: "nat type strict moderate open cgnat double nat stun gaming console port forwarding"
        case .experience: "video streaming buffering netflix youtube gaming ping server region latency"
        }
    }

    var icon: String {
        switch self {
        case .troubleshooter: "stethoscope"
        case .modem: "wifi.router"
        case .ipScanner: "network"
        case .networkMap: "circle.hexagongrid.fill"
        case .wifiSurvey: "house.and.flag.fill"
        case .wifiHeatmap: "map.fill"
        case .traceroute: "point.3.connected.trianglepath.dotted"
        case .portScanner: "door.left.hand.open"
        case .dnsLookup: "globe.americas.fill"
        case .sslChecker: "lock.shield.fill"
        case .whois: "doc.text.magnifyingglass"
        case .subnetCalculator: "square.split.2x2.fill"
        case .wakeOnLAN: "power"
        case .cameraFinder: "web.camera.fill"
        case .wifiSafety: "lock.shield.fill"
        case .dnsBenchmark: "speedometer"
        case .natType: "arrow.left.arrow.right.circle.fill"
        case .experience: "play.tv.fill"
        }
    }

    var tint: Color {
        switch self {
        case .troubleshooter: Color(red: 0.36, green: 0.30, blue: 0.86)
        case .modem: Color(red: 0.36, green: 0.55, blue: 0.95)
        case .ipScanner: Color(red: 0.24, green: 0.45, blue: 0.99)
        case .networkMap: Color(red: 0.20, green: 0.80, blue: 0.65)
        case .wifiSurvey: Color(red: 0.10, green: 0.62, blue: 0.86)
        case .wifiHeatmap: Color(red: 0.93, green: 0.42, blue: 0.20)
        case .traceroute: Color(red: 0.13, green: 0.72, blue: 0.52)
        case .portScanner: Color(red: 0.84, green: 0.28, blue: 0.74)
        case .dnsLookup: Color(red: 0.98, green: 0.62, blue: 0.16)
        case .sslChecker: Color(red: 0.20, green: 0.75, blue: 0.99)
        case .whois: Color(red: 0.99, green: 0.37, blue: 0.37)
        case .subnetCalculator: Color(red: 0.55, green: 0.42, blue: 0.98)
        case .wakeOnLAN: Color(red: 0.98, green: 0.62, blue: 0.16)
        case .cameraFinder: Color(red: 0.86, green: 0.25, blue: 0.35)
        case .wifiSafety: Color(red: 0.16, green: 0.62, blue: 0.40)
        case .dnsBenchmark: Color(red: 0.98, green: 0.62, blue: 0.16)
        case .natType: Color(red: 0.55, green: 0.42, blue: 0.98)
        case .experience: Color(red: 0.84, green: 0.28, blue: 0.74)
        }
    }
}

private enum NetworkToolSection: CaseIterable, Identifiable {
    case localNetwork
    case diagnostics
    case domainSecurity
    case utilities

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .localNetwork: "Local Network"
        case .diagnostics: "Diagnostics"
        case .domainSecurity: "Domain & Security"
        case .utilities: "Utilities"
        }
    }

    var tools: [NetworkTool] {
        switch self {
        case .localNetwork: [.ipScanner, .networkMap, .wifiSurvey, .wifiHeatmap, .cameraFinder]
        case .diagnostics: [.troubleshooter, .modem, .natType, .experience, .traceroute, .portScanner]
        case .domainSecurity: [.wifiSafety, .dnsBenchmark, .dnsLookup, .sslChecker, .whois]
        case .utilities: [.subnetCalculator, .wakeOnLAN]
        }
    }
}

// MARK: - Main View

struct NetworkToolsView: View {
    /// Shared app-wide manager; only the hero card and SpeedTestView observe it,
    /// so live test updates don't invalidate the whole tools list.
    let speedTestManager: SpeedTestManager

    @State private var searchText = ""

    private let backgroundColor = AppTheme.background

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func filteredTools(in section: NetworkToolSection) -> [NetworkTool] {
        guard isSearching else { return section.tools }
        let query = searchText.lowercased()
        return section.tools.filter { $0.searchText.contains(query) }
    }

    @State private var path: [NetworkTool] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    if !isSearching || "speed test download upload ping \(String(localized: "Speed Test"))".lowercased().contains(searchText.lowercased()) {
                        NavigationLink {
                            SpeedTestView(manager: speedTestManager, embedsInNavigationStack: false)
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
        .onReceive(AppRouter.shared.$requestedTool.compactMap { $0 }) { raw in
            AppRouter.shared.requestedTool = nil
            // Deep links and notifications must not open a locked tool.
            if let tool = NetworkTool(rawValue: raw), tool.isFree || PurchaseManager.shared.isPro {
                path = [tool]
            }
        }
        .background(backgroundColor.ignoresSafeArea())
    }

    @ViewBuilder
    private func destinationView(for tool: NetworkTool) -> some View {
        switch tool {
        case .troubleshooter: TroubleshooterView()
        case .modem: ModemView()
        case .ipScanner: IPScannerView()
        case .networkMap: NetworkMapView()
        case .wifiSurvey: WiFiSurveyListView()
        case .wifiHeatmap: WiFiHeatmapListView()
        case .traceroute: TracerouteView()
        case .portScanner: PortScannerView()
        case .dnsLookup: DNSLookupView()
        case .sslChecker: SSLCheckerView()
        case .whois: WhoisView()
        case .subnetCalculator: SubnetCalculatorView()
        case .wakeOnLAN: WakeOnLANView()
        case .cameraFinder: CameraFinderView()
        case .wifiSafety: WiFiSafetyView()
        case .dnsBenchmark: DNSBenchmarkView()
        case .natType: NATTypeView()
        case .experience: ExperienceTestView()
        }
    }
}

// MARK: - Speed Test Hero Card

private struct SpeedTestHeroCard: View {
    @ObservedObject var manager: SpeedTestManager

    private let tint = AppTheme.download

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
                        .appFont(size: 24, weight: .bold, design: .rounded)
                        .foregroundStyle(AppTheme.ink)
                    Text("Measure ping, download and upload speed")
                        .appFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 12)

                Image(systemName: "gauge.with.dots.needle.67percent")
                    .appFont(size: 28, weight: .semibold)
                    .foregroundStyle(tint)
                    .frame(width: 56, height: 56)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if let last = manager.history.first {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Last result · \(last.date, format: .relative(presentation: .named))")
                        .appFont(size: 11, weight: .semibold, design: .rounded)
                        .foregroundStyle(AppTheme.tertiaryText)
                        .textCase(.uppercase)

                    HStack(spacing: 0) {
                        metric(icon: "arrow.down", tint: AppTheme.download, value: mbps(last.downloadSpeed), unit: "Mbps")
                        divider
                        metric(icon: "arrow.up", tint: AppTheme.upload, value: mbps(last.uploadSpeed), unit: "Mbps")
                        divider
                        metric(icon: "timer", tint: AppTheme.ping, value: last.ping.fixed(0), unit: "ms")
                    }
                    .padding(.vertical, 12)
                    .background(AppTheme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            HStack(spacing: 8) {
                Image(systemName: isRunning ? "waveform" : "play.fill")
                    .symbolEffect(.variableColor.iterative, isActive: isRunning)
                Text(isRunning ? "Test in progress" : (manager.history.isEmpty ? "Start Test" : "Test Again"))
            }
            .appFont(size: 16, weight: .semibold, design: .rounded)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tint, in: Capsule())
        }
        .appCard(padding: 20)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.separator)
            .frame(width: 1, height: 28)
    }

    private func metric(icon: String, tint: Color, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .appFont(size: 11, weight: .bold)
                    .foregroundStyle(tint)
                Text(value)
                    .appFont(size: 17, weight: .bold, design: .rounded)
                    .monospacedDigit()
            }
            .foregroundStyle(AppTheme.ink)
            Text(unit)
                .appFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func mbps(_ bytesPerSecond: Double) -> String {
        (bytesPerSecond * 8 / 1_000_000).fixed(1)
    }
}

// MARK: - Tool Section

private struct ToolSectionView: View {
    let title: LocalizedStringKey
    let tools: [NetworkTool]
    @ObservedObject private var purchaseManager = PurchaseManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .appFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundStyle(AppTheme.ink.opacity(0.5))
                .textCase(.uppercase)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(tools) { tool in
                    let isLocked = !tool.isFree && !purchaseManager.isPro
                    if isLocked {
                        NavigationLink(value: tool) {
                            ToolRow(tool: tool, isLocked: true)
                        }
                        .buttonStyle(RowButtonStyle())
                        .proGated(feature: .networkTools)
                    } else {
                        NavigationLink(value: tool) {
                            ToolRow(tool: tool, isLocked: false)
                        }
                        .buttonStyle(RowButtonStyle())
                    }

                    if tool != tools.last {
                        Divider()
                            .overlay(AppTheme.ink.opacity(0.08))
                            .padding(.leading, 70)
                    }
                }
            }
            .background(AppTheme.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.ink.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Tool Row

private struct ToolRow: View {
    let tool: NetworkTool
    var isLocked = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: tool.icon)
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(tool.tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(tool.name)
                    .appFont(size: 16, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.ink)
                Text(tool.description)
                    .appFont(size: 12, weight: .regular, design: .rounded)
                    .foregroundStyle(AppTheme.ink.opacity(0.55))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            if isLocked {
                ProBadge()
            }

            Image(systemName: "chevron.right")
                .appFont(size: 13, weight: .semibold)
                .foregroundStyle(AppTheme.ink.opacity(0.3))
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
            .background(configuration.isPressed ? AppTheme.ink.opacity(0.08) : Color.clear)
    }
}

#Preview {
    NetworkToolsView(speedTestManager: SpeedTestManager())
        .preferredColorScheme(.dark)
}
