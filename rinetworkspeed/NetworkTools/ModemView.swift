//
//  ModemView.swift
//  rinetworkspeed
//
//  "Modem & Line": the router's line rate, WAN address, traffic counters and
//  UPnP port mappings, with the plan / line / speed test comparison.
//

import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class ModemViewModel: ObservableObject {
    @Published private(set) var reading: ModemReading?
    @Published private(set) var isReading = false
    @Published private(set) var failure: UPnPError?
    @Published private(set) var notOnWiFi = false

    private var task: Task<Void, Never>?

    func read() {
        task?.cancel()
        failure = nil
        notOnWiFi = false
        isReading = true

        task = Task {
            defer { isReading = false }
            let details = WiFiInfoManager.localInterfaceDetails()
            guard details.ipAddress != nil else {
                notOnWiFi = true
                return
            }
            do {
                let result = try await UPnPGateway.read(gateway: details.routerIP, interfaceAddress: details.ipAddress)
                guard !Task.isCancelled else { return }
                reading = result
                ModemReadingStore.save(result)
            } catch let error as UPnPError {
                failure = error
            } catch {
                failure = .descriptionUnavailable
            }
        }
    }

    var comparison: LineComparison? {
        guard let reading, reading.isLineRate, let line = reading.downstreamMbps, line > 0 else { return nil }
        return LineComparison(
            lineMbps: line,
            planMbps: InternetPlan.load()?.downloadMbps,
            testMbps: LineComparison.recentWiFiDownloadMbps(SpeedTestHistoryStore.shared.results)
        )
    }
}

// MARK: - Main View

struct ModemView: View {
    @StateObject private var vm = ModemViewModel()
    private let accent = Color(red: 0.36, green: 0.55, blue: 0.95)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                heroCard

                if vm.notOnWiFi {
                    messageCard(icon: "wifi.slash", title: "Not on Wi-Fi",
                                message: "Join the Wi-Fi network of the router you want to read.")
                } else if let failure = vm.failure {
                    messageCard(icon: "exclamationmark.triangle.fill", title: "Couldn't read the router",
                                message: message(for: failure))
                } else if let reading = vm.reading {
                    if let comparison = vm.comparison {
                        ModemComparisonCard(comparison: comparison)
                    }
                    lineSection(reading)
                    connectionSection(reading)
                    trafficSection(reading)
                    portsSection(reading)
                    deviceSection(reading)
                } else if !vm.isReading {
                    AppEmptyState(
                        icon: "wifi.router",
                        title: "No Reading Yet",
                        message: "Read your router to see the line speed it reports, its internet address and the ports it has opened."
                    )
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .appPageBackground()
        .navigationTitle("Modem & Line")
        .navigationBarTitleDisplayMode(.large)
        .toolReport(vm) { $0.reportText }
        .onAppear {
            if vm.reading == nil && !vm.isReading { vm.read() }
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "wifi.router")
                    .appFont(size: 24, weight: .semibold)
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.ink.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your router's view")
                        .appFont(size: 19, weight: .bold, design: .rounded)
                        .foregroundStyle(AppTheme.ink)
                    Text("Reads the line speed, internet address and open ports from your router over UPnP.")
                        .appFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AppTheme.ink.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button {
                vm.read()
            } label: {
                HStack(spacing: 8) {
                    if vm.isReading {
                        ProgressView().tint(accent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(vm.isReading ? "Reading…" : "Read Router")
                }
            }
            .buttonStyle(AppPrimaryButtonStyle(variant: .inverted, tint: accent))
            .disabled(vm.isReading)
        }
        .appHeroCard(tint: accent)
    }

    // MARK: Sections

    private func lineSection(_ reading: ModemReading) -> some View {
        AppSection(
            "Line",
            footer: reading.isLineRate
                ? "On DSL this is the rate the modem synced with the exchange, the ceiling for every speed test."
                : "On this connection type the router reports the speed of its own WAN port, not the speed of your internet line."
        ) {
            valueRow(icon: "cable.connector", title: "Connection type", value: reading.accessType)
            AppRowDivider()
            valueRow(icon: "bolt.horizontal.fill", title: "Link", value: reading.linkStatus)
            AppRowDivider()
            valueRow(icon: "arrow.down", title: reading.isLineRate ? "Line rate down" : "WAN port down",
                     value: reading.downstreamMbps.map { "\($0.fixed(1)) Mbps" })
            AppRowDivider()
            valueRow(icon: "arrow.up", title: reading.isLineRate ? "Line rate up" : "WAN port up",
                     value: reading.upstreamMbps.map { "\($0.fixed(1)) Mbps" })
        }
    }

    private func connectionSection(_ reading: ModemReading) -> some View {
        AppSection("Internet Connection", footer: natNote(reading)) {
            valueRow(icon: "globe", title: "Router's internet address", value: reading.externalIP)
            AppRowDivider()
            valueRow(icon: "checkmark.circle", title: "Status", value: reading.connectionStatus)
            AppRowDivider()
            valueRow(icon: "clock", title: "Connected for", value: reading.uptimeSeconds.map(Self.duration))
        }
    }

    /// Explains a non-public WAN address (carrier-grade NAT or a second router).
    private func natNote(_ reading: ModemReading) -> LocalizedStringKey? {
        guard let ip = reading.externalIP, let scope = IPv4Scope(ip) else { return nil }
        switch scope {
        case .sharedAddressSpace:
            return "This is a carrier-grade NAT address: your provider shares one public address between several customers. Incoming connections and port forwarding won't work."
        case .privateNetwork:
            return "This is a private address, so another router sits between this one and the internet (double NAT). Port forwarding has to be set up on both."
        case .special, .publicInternet:
            return nil
        }
    }

    private func trafficSection(_ reading: ModemReading) -> some View {
        AppSection("Traffic Since the Router Started", footer: "Many routers count up to 4 GB and then start again from zero.") {
            valueRow(icon: "arrow.down.circle", title: "Received",
                     value: reading.totalBytesReceived.map { $0.formatted(.byteCount(style: .decimal)) })
            AppRowDivider()
            valueRow(icon: "arrow.up.circle", title: "Sent",
                     value: reading.totalBytesSent.map { $0.formatted(.byteCount(style: .decimal)) })
        }
    }

    private func portsSection(_ reading: ModemReading) -> some View {
        AppSection("Ports Opened by Devices", footer: "Apps and devices can open ports on the router through UPnP. Remove any you don't recognise in the router's settings.") {
            if reading.portMappings.isEmpty {
                valueRow(icon: "lock.fill", title: "Opened ports", value: String(localized: "None"))
            } else {
                ForEach(Array(reading.portMappings.enumerated()), id: \.offset) { index, mapping in
                    if index > 0 { AppRowDivider() }
                    AppRow(icon: mapping.enabled ? "door.left.hand.open" : "door.left.hand.closed",
                           tint: mapping.enabled ? AppTheme.warning : AppTheme.ink.opacity(0.3),
                           verbatimTitle: "\(mapping.transport) \(mapping.externalPort) → \(mapping.internalClient):\(mapping.internalPort)") {
                        if let description = mapping.description {
                            Text(verbatim: description)
                                .appFont(size: 13, weight: .medium, design: .rounded)
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func deviceSection(_ reading: ModemReading) -> some View {
        AppSection("Router") {
            valueRow(icon: "tag", title: "Name", value: reading.friendlyName)
            AppRowDivider()
            valueRow(icon: "shippingbox", title: "Model", value: reading.modelName)
            AppRowDivider()
            valueRow(icon: "building.2", title: "Manufacturer", value: reading.manufacturer)
            AppRowDivider()
            valueRow(icon: "network", title: "Address", value: reading.routerAddress)
        }
    }

    // MARK: Helpers

    private func valueRow(icon: String, title: LocalizedStringKey, value: String?) -> some View {
        AppRow(icon: icon, tint: accent, title: title) {
            Text(verbatim: value ?? "—")
                .appFont(size: 15, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(value == nil ? AppTheme.tertiaryText : AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .textSelection(.enabled)
        }
    }

    private func messageCard(icon: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AppIconTile(systemName: icon, tint: AppTheme.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(size: 16, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)
                Text(message)
                    .appFont(size: 13, weight: .regular, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .appCard()
    }

    private func message(for failure: UPnPError) -> LocalizedStringKey {
        switch failure {
        case .notFound:
            return "The router didn't answer. Turn on UPnP in the router's settings; some routers don't support it."
        case .descriptionUnavailable:
            return "The router answered, but its device description couldn't be read."
        case .noWANService:
            return "The router answered but doesn't share its internet connection details. It may be a mesh point or access point, with the modem being another device."
        }
    }

    static func duration(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds) s"
    }
}

// MARK: - Comparison card

private struct ModemComparisonCard: View {
    let comparison: LineComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader("Plan, Line and Tests")
            VStack(alignment: .leading, spacing: 14) {
                AppAdaptiveStack(spacing: 12) {
                    value(title: "Plan", mbps: comparison.planMbps)
                    value(title: "Line", mbps: comparison.lineMbps)
                    value(title: "Your tests", mbps: comparison.testMbps)
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Text(message)
                        .appFont(size: 14, weight: .medium, design: .rounded)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .appCard(padding: 14)
            .accessibilityElement(children: .combine)
        }
    }

    private func value(title: LocalizedStringKey, mbps: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .appFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: mbps.map { $0.fixed(0) } ?? "--")
                    .appFont(size: 20, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.ink)
                Text(verbatim: "Mbps")
                    .appFont(size: 10, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icon: String {
        switch comparison.verdict {
        case .lineBelowPlan, .homeBelowLine: return "exclamationmark.triangle.fill"
        case .consistent: return "checkmark.circle.fill"
        case .needsPlan, .needsTests: return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch comparison.verdict {
        case .lineBelowPlan, .homeBelowLine: return AppTheme.warning
        case .consistent: return AppTheme.ping
        case .needsPlan, .needsTests: return AppTheme.secondaryText
        }
    }

    private var message: LocalizedStringKey {
        switch comparison.verdict {
        case .lineBelowPlan:
            return "Your line syncs below your plan, so no speed test can reach the plan. The limit is the line itself (distance to the exchange, cabling or line quality), not your Wi-Fi. Ask your provider to check the line."
        case .homeBelowLine:
            return "Your line is fine, but your tests fall well short of it. The gap is inside your home: Wi-Fi, the router or other devices using the connection."
        case .consistent:
            return "Line, plan and tests agree."
        case .needsPlan:
            return "Enter your plan in Settings → Internet Plan to compare it with the line."
        case .needsTests:
            return "Run a speed test on this Wi-Fi to compare it with the line."
        }
    }
}
