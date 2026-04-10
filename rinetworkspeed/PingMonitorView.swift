//
//  PingMonitorView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Charts

private enum PingHostOption: String, CaseIterable, Identifiable {
    case cloudflare
    case google
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cloudflare:
            return "Cloudflare"
        case .google:
            return "Google"
        case .custom:
            return "Ozel"
        }
    }

    var host: String {
        switch self {
        case .cloudflare:
            return "1.1.1.1"
        case .google:
            return "8.8.8.8"
        case .custom:
            return ""
        }
    }
}

private struct PingStat: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let color: Color
}

struct PingMonitorView: View {
    @ObservedObject var monitor: PingMonitor
    @State private var selectedHost: PingHostOption = .cloudflare
    @State private var customHost: String = ""
    @State private var pulseScale: Double = 1
    @State private var pulseOpacity: Double = 0.5

    private let backgroundColor = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)

    private var stats: [PingStat] {
        [
            PingStat(title: "Min Ping", value: formatPing(monitor.minPing), color: .green),
            PingStat(title: "Max Ping", value: formatPing(monitor.maxPing), color: .orange),
            PingStat(title: "Ortalama Ping", value: formatPing(monitor.avgPing), color: .yellow),
            PingStat(title: "Gonderilen", value: "\(monitor.packetsSent)", color: .white),
            PingStat(title: "Kayip", value: "\(monitor.packetsLost)", color: .red),
            PingStat(title: "Paket Kaybi", value: String(format: "%.0f%%", monitor.packetLossPercent), color: .pink)
        ]
    }

    private var maxChartValue: Double {
        let values = monitor.pingHistory.map { $0.latency < 0 ? 0 : $0.latency }
        return max(20, (values.max() ?? 0) * 1.2)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    statusSection
                    chartCard
                    statsGrid
                    hostSelectorCard
                    controlButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Ping Monitor")
            .onAppear {
                startIfNeeded()
                startPulseAnimation()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                monitor.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                startIfNeeded()
            }
        }
        .background(backgroundColor.ignoresSafeArea())
    }

    private var statusSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .strokeBorder(statusColor.opacity(0.16), lineWidth: 14)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
                    .frame(width: 160, height: 160)

                Circle()
                    .stroke(statusColor.opacity(0.35), lineWidth: 8)
                    .frame(width: 160, height: 160)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)

                VStack(spacing: 6) {
                    Text(monitor.currentPing < 0 ? "--" : String(format: "%.0f", monitor.currentPing))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("ms")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                    Text(statusLabel)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(statusColor)
                }
            }
            .shadow(color: statusColor.opacity(0.22), radius: 24, x: 0, y: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Canli Grafik")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Chart {
                ForEach(monitor.pingHistory) { sample in
                    if sample.latency >= 0 {
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Latency", sample.latency)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(statusColor)
                    }
                }

                ForEach(monitor.pingHistory.filter { $0.latency < 0 }) { sample in
                    PointMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Latency", maxChartValue * 0.9)
                    )
                    .symbolSize(40)
                    .foregroundStyle(.red)
                }

                RectangleMark(
                    xStart: .value("Start", Date().addingTimeInterval(-60)),
                    xEnd: .value("End", Date()),
                    yStart: .value("Low", 0),
                    yEnd: .value("Excellent", 20)
                )
                .foregroundStyle(.green.opacity(0.08))
            }
            .chartXScale(domain: Date().addingTimeInterval(-60)...Date())
            .chartYScale(domain: 0...maxChartValue)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.minute().second()))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.white.opacity(0.05))
                    AxisValueLabel {
                        if let ping = value.as(Double.self) {
                            Text("\(Int(ping))")
                        }
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(height: 160)
        }
        .padding(18)
        .pingCardStyle()
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 8) {
                    Text(stat.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                    Text(stat.value)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(stat.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .pingCardStyle()
            }
        }
    }

    private var hostSelectorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Host Secici")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Picker("Host", selection: $selectedHost) {
                ForEach(PingHostOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedHost) { _, newValue in
                applyHostChange(for: newValue)
            }

            if selectedHost == .custom {
                TextField("Host girin", text: $customHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .foregroundStyle(.white)
                    .onSubmit {
                        applyCustomHost()
                    }
            }
        }
        .padding(18)
        .pingCardStyle()
    }

    private var controlButton: some View {
        VStack(spacing: 10) {
            Button {
                if monitor.isRunning {
                    monitor.stop()
                } else {
                    startIfNeeded()
                }
            } label: {
                Text(monitor.isRunning ? "Durdur" : "Baslat")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                monitor.isRunning
                                    ? AnyShapeStyle(LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing))
                                    : AnyShapeStyle(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                            )
                    )
            }
            .buttonStyle(.plain)

            Text("\(activeHostText) adresine ping atiliyor...")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var statusColor: Color {
        switch monitor.status {
        case .excellent:
            return .green
        case .good:
            return Color(red: 134 / 255, green: 239 / 255, blue: 172 / 255)
        case .fair:
            return .yellow
        case .poor:
            return .orange
        case .timeout:
            return .red
        }
    }

    private var statusLabel: String {
        switch monitor.status {
        case .excellent:
            return "Mukemmel"
        case .good:
            return "Iyi"
        case .fair:
            return "Orta"
        case .poor:
            return "Zayif"
        case .timeout:
            return "Zaman Asimi"
        }
    }

    private var activeHostText: String {
        selectedHost == .custom ? customHost : selectedHost.host
    }

    private func startIfNeeded() {
        let host = selectedHost == .custom ? customHost : selectedHost.host
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        monitor.start(host: host)
    }

    private func applyHostChange(for option: PingHostOption) {
        monitor.stop()
        monitor.reset()

        if option != .custom {
            monitor.start(host: option.host)
        }
    }

    private func applyCustomHost() {
        monitor.stop()
        monitor.reset()
        startIfNeeded()
    }

    private func startPulseAnimation() {
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
            pulseScale = 1.3
            pulseOpacity = 0
        }
    }

    private func formatPing(_ value: Double) -> String {
        value <= 0 ? "--" : String(format: "%.0f ms", value)
    }
}

private struct PingCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 6)
    }
}

private extension View {
    func pingCardStyle() -> some View {
        modifier(PingCardModifier())
    }
}

#Preview {
    PingMonitorView(monitor: PingMonitor())
}
