//
//  SpeedTestView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI

struct SpeedTestView: View {
    @StateObject private var manager = SpeedTestManager()
    @State private var animatePulse = false

    private let backgroundColor = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    private let pingColor = Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255)
    private let downloadColor = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    private let uploadColor = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    gaugeSection

                    if isTesting {
                        progressSection
                    }

                    controlButton

                    if manager.state == .finished {
                        resultCards
                    }

                    historySection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Hiz Testi")
        }
        .background(backgroundColor.ignoresSafeArea())
        .onAppear {
            animatePulse = isTesting
        }
        .onChange(of: isTesting) { _, newValue in
            animatePulse = newValue
        }
    }

    private var gaugeSection: some View {
        VStack(spacing: 18) {
            HalfGaugeView(
                progress: gaugeProgress,
                color: gaugeColor,
                glowColor: gaugeColor,
                valueText: formattedCurrentSpeed.value,
                unitText: formattedCurrentSpeed.unit,
                subtitle: gaugeSubtitle
            )
            .frame(height: 260)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 12) {
            progressBar(title: "Download", progress: manager.downloadProgress, color: downloadColor)
            progressBar(title: "Upload", progress: manager.uploadProgress, color: uploadColor)
        }
        .padding(18)
        .speedTestCardStyle()
    }

    private var controlButton: some View {
        Button {
            if isTesting {
                manager.cancelTest()
            } else {
                Task {
                    await manager.startTest()
                }
            }
        } label: {
            Text(isTesting ? "Iptal Et" : "Testi Baslat")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    Capsule(style: .continuous)
                        .fill(isTesting ? LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [downloadColor, Color.cyan], startPoint: .leading, endPoint: .trailing))
                )
                .scaleEffect(animatePulse ? 1.02 : 1)
                .shadow(color: (isTesting ? Color.red : downloadColor).opacity(0.35), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .animation(isTesting ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .easeInOut(duration: 0.2), value: animatePulse)
    }

    private var resultCards: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                resultCard(title: "Ping", value: String(format: "%.0f", manager.ping), unit: "ms", icon: "timer", color: pingColor)
                resultCard(title: "Download", value: formatRateValue(manager.finalDownload), unit: "MB/s", icon: "arrow.down.circle.fill", color: downloadColor)
                resultCard(title: "Upload", value: formatRateValue(manager.finalUpload), unit: "MB/s", icon: "arrow.up.circle.fill", color: uploadColor)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Network Kalite Skoru")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Text(networkGrade)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .speedTestCardStyle()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: manager.state)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Gecmis Testler")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button("Gecmisi Temizle") {
                    manager.clearHistory()
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .buttonStyle(.plain)
            }

            if manager.history.isEmpty {
                Text("Henuz kayitli hiz testi yok.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .speedTestCardStyle()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(manager.history) { result in
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)

                                HStack(spacing: 12) {
                                    historyMetric(systemImage: "arrow.down.circle.fill", value: formatRateValue(result.downloadSpeed), unit: "MB/s", color: downloadColor)
                                    historyMetric(systemImage: "arrow.up.circle.fill", value: formatRateValue(result.uploadSpeed), unit: "MB/s", color: uploadColor)
                                    historyMetric(systemImage: "timer", value: String(format: "%.0f", result.ping), unit: "ms", color: pingColor)
                                }
                            }

                            Spacer()
                        }
                        .padding(16)
                        .speedTestCardStyle()
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(result)
                            } label: {
                                Label("Sil", systemImage: "trash.fill")
                            }
                        }
                    }
                }
            }
        }
    }

    private func resultCard(title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .speedTestCardStyle()
    }

    private func historyMetric(systemImage: String, value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .foregroundStyle(.white.opacity(0.82))
            Text(unit)
                .foregroundStyle(.white.opacity(0.45))
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
    }

    private func progressBar(title: String, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: geometry.size.width * max(0, min(progress, 1)))
                        .animation(.easeInOut(duration: 0.2), value: progress)
                }
            }
            .frame(height: 8)
        }
    }

    private func delete(_ result: SpeedTestResult) {
        if let index = manager.history.firstIndex(where: { $0.id == result.id }) {
            manager.deleteHistory(at: IndexSet(integer: index))
        }
    }

    private var currentSpeed: Double {
        switch manager.state {
        case .downloadTesting:
            return manager.downloadSpeed
        case .uploadTesting:
            return manager.uploadSpeed
        default:
            return max(manager.finalDownload, manager.finalUpload)
        }
    }

    private var formattedCurrentSpeed: (value: String, unit: String) {
        let mbPerSecond = currentSpeed / (1024 * 1024)
        return (String(format: "%.1f", mbPerSecond), "MB/s")
    }

    private var gaugeProgress: Double {
        let maxScale = max(currentSpeed, manager.finalDownload, manager.finalUpload, 100 * 1024 * 1024)
        return min(1, currentSpeed / maxScale)
    }

    private var gaugeColor: Color {
        switch manager.state {
        case .idle, .finished, .failed:
            return downloadColor
        case .downloadTesting:
            return downloadColor
        case .uploadTesting:
            return uploadColor
        }
    }

    private var gaugeSubtitle: String {
        switch manager.state {
        case .idle:
            return "Hazir"
        case .downloadTesting:
            return "Indirme Testi..."
        case .uploadTesting:
            return "Yukleme Testi..."
        case .finished:
            return "Test Tamamlandi"
        case .failed:
            return "Test Basarisiz"
        }
    }

    private var isTesting: Bool {
        manager.state == .downloadTesting || manager.state == .uploadTesting
    }

    private var networkGrade: String {
        let downloadMB = manager.finalDownload / (1024 * 1024)
        let uploadMB = manager.finalUpload / (1024 * 1024)

        if manager.ping < 20, downloadMB > 60, uploadMB > 25 {
            return "A"
        } else if manager.ping < 35, downloadMB > 30, uploadMB > 12 {
            return "B"
        } else if manager.ping < 60, downloadMB > 15, uploadMB > 6 {
            return "C"
        } else if manager.ping < 90, downloadMB > 5, uploadMB > 2 {
            return "D"
        }
        return "F"
    }

    private func formatRateValue(_ bytesPerSecond: Double) -> String {
        String(format: "%.1f", bytesPerSecond / (1024 * 1024))
    }
}

private struct HalfGaugeView: View {
    let progress: Double
    let color: Color
    let glowColor: Color
    let valueText: String
    let unitText: String
    let subtitle: String

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.5, to: 1.0)
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(180))

            Circle()
                .trim(from: 0.5, to: 0.5 + (0.5 * max(0, min(progress, 1))))
                .stroke(color, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(180))
                .shadow(color: glowColor.opacity(0.4), radius: 30, x: 0, y: 0)
                .animation(.easeInOut(duration: 0.2), value: progress)

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(valueText)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(unitText)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text(subtitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .offset(y: 34)
        }
        .padding(.horizontal, 10)
    }
}

private struct SpeedTestCardModifier: ViewModifier {
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
    func speedTestCardStyle() -> some View {
        modifier(SpeedTestCardModifier())
    }
}

#Preview {
    SpeedTestView()
}
