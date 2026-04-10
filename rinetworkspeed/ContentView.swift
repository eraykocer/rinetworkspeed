//
//  ContentView.swift
//  rinetworkspeed
//
//  Created by Eray Kocer on 9.04.2026.
//

import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject var monitor: NetworkStatsMonitor
    @ObservedObject var dataUsage: DataUsageMonitor
    @ObservedObject var speedTestManager: SpeedTestManager
    @ObservedObject var pingMonitor: PingMonitor
    @Binding var selectedTab: Int
    @AppStorage("speedUnit") private var speedUnit: String = "bytes"
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled: Bool = true
    @State private var showingSpeedTest = false
    @State private var showingPingMonitor = false

    private let backgroundColor = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    private let downloadColor = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    private let uploadColor = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                headerBar
                speedCards
                miniChartCard
                todayUsageCard
                connectionDetailsCard
                toolsCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(backgroundColor.ignoresSafeArea())
        .onChange(of: liveActivityEnabled) { _, isEnabled in
            withAnimation(.easeInOut(duration: 0.3)) {
                if isEnabled {
                    monitor.applyLiveActivitySetting()
                } else {
                    monitor.stopLiveActivity()
                }
            }
        }
    }

    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tools")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 14) {
                toolButton(
                    title: "Speed Test",
                    subtitle: "Real download & upload measurement",
                    systemImage: "bolt.fill",
                    color: downloadColor
                ) {
                    showingSpeedTest = true
                }
                .proGated(feature: .speedTest)

                toolButton(
                    title: "Ping Monitor",
                    subtitle: "Live latency & packet loss",
                    systemImage: "dot.radiowaves.left.and.right",
                    color: uploadColor
                ) {
                    showingPingMonitor = true
                }
                .proGated(feature: .pingMonitor)
            }
        }
        .padding(18)
        .premiumCardStyle()
        .sheet(isPresented: $showingSpeedTest) {
            SpeedTestView(manager: speedTestManager)
        }
        .sheet(isPresented: $showingPingMonitor) {
            PingMonitorView(monitor: pingMonitor)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: activeConnectionIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(activeConnectionColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.connectionName)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(activeConnectionSubtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer()

            Button {
                liveActivityEnabled.toggle()
            } label: {
                Image(systemName: liveActivityEnabled ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(liveActivityEnabled ? .red : .green)
            }
            .buttonStyle(.plain)
            .proGated(feature: .widget)
        }
        .padding(18)
        .premiumCardStyle()
    }

    private var speedCards: some View {
        HStack(spacing: 14) {
            speedCard(
                title: "Download",
                systemImage: "arrow.down.circle.fill",
                color: downloadColor,
                speed: primaryDownloadSpeed
            )

            speedCard(
                title: "Upload",
                systemImage: "arrow.up.circle.fill",
                color: uploadColor,
                speed: primaryUploadSpeed
            )
        }
    }

    private var miniChartCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Last 60 sec")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))

                Spacer()

                Text(monitor.formatSpeed(chartMaxSpeed))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
            }

            CompactSpeedChart(monitor: monitor)
                .frame(height: 80)

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedTab = 1
                }
            } label: {
                HStack {
                    Text("Detailed Graph")
                    Spacer()
                    Text("->")
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .premiumCardStyle()
    }

    private var todayUsageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today's Usage")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = 2
                    }
                } label: {
                    Text("Details ->")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 14) {
                usageTile(
                    title: "WiFi",
                    value: dataUsage.formatBytes(dataUsage.todayWifiBytes),
                    color: downloadColor
                )

                usageTile(
                    title: "Cellular",
                    value: dataUsage.formatBytes(dataUsage.todayCellularBytes),
                    color: uploadColor
                )
            }
        }
        .padding(18)
        .premiumCardStyle()
    }

    private var connectionDetailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connection Details")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            detailRow(title: "Ping / Latency", value: latencyText)
            detailRow(title: "WiFi RSSI", value: monitor.wifiSignalDescription)
            detailRow(title: "IP Address", value: monitor.ipAddress)
        }
        .padding(18)
        .premiumCardStyle()
    }

    private func speedCard(title: String, systemImage: String, color: Color, speed: Double) -> some View {
        let components = monitor.formattedSpeedComponents(speed)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(components.value)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(components.unit)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .animation(.easeOut(duration: 0.2), value: components.value)

                Text(speedUnit == "bits" ? "Megabit speed format" : "Byte speed format")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .premiumCardStyle()
    }

    private func usageTile(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(color.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        )
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: value)
        }
    }

    private func toolButton(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var activeConnectionIcon: String {
        switch monitor.activeInterface {
        case .wifi:
            return "wifi"
        case .cellular:
            return "antenna.radiowaves.left.and.right"
        case .none:
            return "wifi.slash"
        }
    }

    private var activeConnectionColor: Color {
        switch monitor.activeInterface {
        case .wifi:
            return downloadColor
        case .cellular:
            return uploadColor
        case .none:
            return .white.opacity(0.5)
        }
    }

    private var activeConnectionSubtitle: String {
        switch monitor.activeInterface {
        case .wifi:
            return "Kablosuz baglanti aktif"
        case .cellular:
            return "Mobil veri aktif"
        case .none:
            return "Ag baglantisi algilanmadi"
        }
    }

    private var primaryDownloadSpeed: Double {
        switch monitor.activeInterface {
        case .wifi:
            return monitor.wifiDownloadSpeed
        case .cellular:
            return monitor.cellularDownloadSpeed
        case .none:
            return monitor.downloadSpeed
        }
    }

    private var primaryUploadSpeed: Double {
        switch monitor.activeInterface {
        case .wifi:
            return monitor.wifiUploadSpeed
        case .cellular:
            return monitor.cellularUploadSpeed
        case .none:
            return monitor.uploadSpeed
        }
    }

    private var chartMaxSpeed: Double {
        let cutoff = Date().addingTimeInterval(-60)
        return monitor.history.lazy.filter { $0.timestamp >= cutoff }.reduce(0) { partialResult, sample in
            max(partialResult, sample.downloadSpeed, sample.uploadSpeed)
        }
    }

    private var latencyText: String {
        guard let latency = monitor.latencyMs else { return "--" }
        return String(format: "%.0f ms", latency)
    }
}

private struct CompactSpeedChart: View {
    @ObservedObject var monitor: NetworkStatsMonitor

    private let downloadColor = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    private let uploadColor = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)

    private var recentHistory: [SpeedSample] {
        let cutoff = Date().addingTimeInterval(-60)
        return monitor.history.filter { $0.timestamp >= cutoff }
    }

    var body: some View {
        Chart(recentHistory) { sample in
            AreaMark(
                x: .value("Time", sample.timestamp),
                y: .value("Download", sample.downloadSpeed)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                .linearGradient(
                    colors: [downloadColor.opacity(0.28), downloadColor.opacity(0.01)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Download", sample.downloadSpeed)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(downloadColor)
            .lineStyle(StrokeStyle(lineWidth: 2))

            AreaMark(
                x: .value("Time", sample.timestamp),
                y: .value("Upload", sample.uploadSpeed)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                .linearGradient(
                    colors: [uploadColor.opacity(0.24), uploadColor.opacity(0.01)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Upload", sample.uploadSpeed)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(uploadColor)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
    }
}

private struct PremiumCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 6)
    }
}

private extension View {
    func premiumCardStyle() -> some View {
        modifier(PremiumCardModifier())
    }
}

#Preview {
    ContentView(
        monitor: NetworkStatsMonitor(),
        dataUsage: DataUsageMonitor(),
        speedTestManager: SpeedTestManager(),
        pingMonitor: PingMonitor(),
        selectedTab: .constant(0)
    )
}
