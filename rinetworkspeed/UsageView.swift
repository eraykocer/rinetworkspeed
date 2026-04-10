//
//  UsageView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Charts

private struct UsageChartBar: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let type: String
    let bytes: UInt64
    let isToday: Bool
}

struct UsageView: View {
    @ObservedObject var dataUsage: DataUsageMonitor
    @AppStorage("dataLimitEnabled") private var dataLimitEnabled: Bool = false
    @AppStorage("dataLimitGB") private var dataLimitGB: Double = 5.0
    @AppStorage("dataLimitResetDay") private var dataLimitResetDay: Int = 1

    @State private var selectedDay: DailyUsageSample?
    @State private var showingResetAlert = false

    private let backgroundColor = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    private let wifiColor = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    private let cellularColor = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)

    private var todayTotal: UInt64 {
        dataUsage.todayWifiBytes + dataUsage.todayCellularBytes
    }

    private var weeklySamples: [DailyUsageSample] {
        dataUsage.usageForLast7Days()
    }

    private var monthlySummary: (wifi: UInt64, cellular: UInt64, dailyAverage: UInt64, projectedMonthly: UInt64) {
        dataUsage.monthlySummary()
    }

    private var progressTarget: Double {
        if dataLimitEnabled {
            return dataLimitGB * 1024 * 1024 * 1024
        }

        let weeklyTotal = Double(dataUsage.weeklyWifiBytes + dataUsage.weeklyCellularBytes)
        let average = weeklyTotal > 0 ? weeklyTotal / 7 : Double(max(todayTotal, 1))
        return max(average, 1)
    }

    private var ringProgress: Double {
        min(1, Double(todayTotal) / progressTarget)
    }

    private var ringColor: Color {
        if dataLimitEnabled && Double(todayTotal) > progressTarget {
            return .red
        }
        return todayTotal > dataUsage.todayWifiBytes ? cellularColor : wifiColor
    }

    private var chartBars: [UsageChartBar] {
        weeklySamples.flatMap { sample in
            let isToday = Calendar.current.isDateInToday(sample.date)
            return [
                UsageChartBar(date: sample.date, label: weekdayLabel(for: sample.date), type: "WiFi", bytes: sample.wifiBytes, isToday: isToday),
                UsageChartBar(date: sample.date, label: weekdayLabel(for: sample.date), type: "Cellular", bytes: sample.cellularBytes, isToday: isToday)
            ]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if todayTotal == 0 && weeklySamples.allSatisfy({ $0.wifiBytes == 0 && $0.cellularBytes == 0 }) {
                        placeholderCard
                    } else {
                        heroCard
                        weeklyChartCard
                        monthlySummaryCard
                        resetInfoCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Veri Kullanimi")
            .alert("Bugunku sayac sifirlansin mi?", isPresented: $showingResetAlert) {
                Button("Iptal", role: .cancel) {}
                Button("Sifirla", role: .destructive) {
                    dataUsage.resetToday()
                }
            } message: {
                Text("Bugunku WiFi ve Cellular sayaclari sifirlanacak.")
            }
        }
        .background(backgroundColor.ignoresSafeArea())
    }

    private var heroCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 16, lineCap: .round))

                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: ringProgress)

                VStack(spacing: 6) {
                    if dataLimitEnabled && Double(todayTotal) > progressTarget {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.red)
                    }

                    Text(dataUsage.formatBytes(todayTotal))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Text("Bugunku Toplam")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.54))
                }
            }
            .frame(width: 150, height: 150)

            VStack(spacing: 10) {
                usageRow(title: "WiFi", value: dataUsage.formatBytes(dataUsage.todayWifiBytes), color: wifiColor)
                usageRow(title: "Cellular", value: dataUsage.formatBytes(dataUsage.todayCellularBytes), color: cellularColor)
            }

            if dataLimitEnabled {
                Text(limitMessage)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Double(todayTotal) > progressTarget ? .red : .white.opacity(0.76))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .padding(18)
        .usageCardStyle()
    }

    private var weeklyChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Haftalik Grafik")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Chart(chartBars) { bar in
                BarMark(
                    x: .value("Day", bar.date, unit: .day),
                    y: .value("Usage", bar.bytes)
                )
                .position(by: .value("Type", bar.type))
                .foregroundStyle(by: .value("Type", bar.type))
                .opacity(bar.isToday ? 1 : 0.76)
                .annotation(position: .top, spacing: 4) {
                    if bar.isToday && selectedDay == nil {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 24, height: 3)
                    }
                }
            }
            .chartForegroundStyleScale([
                "WiFi": wifiColor,
                "Cellular": cellularColor
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(weekdayLabel(for: date))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.58))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.white.opacity(0.05))
                    AxisValueLabel {
                        if let bytes = value.as(Double.self) {
                            Text(axisLabel(bytes))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.58))
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let frame = geometry[proxy.plotAreaFrame]
                                    let xPosition = value.location.x - frame.origin.x
                                    guard xPosition >= 0,
                                          xPosition <= proxy.plotAreaSize.width,
                                          let date: Date = proxy.value(atX: xPosition) else {
                                        return
                                    }
                                    selectedDay = nearestDay(to: date)
                                }
                                .onEnded { _ in
                                    selectedDay = nil
                                }
                        )
                }
            }
            .frame(height: 200)

            if let selectedDay {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedDay.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.54))
                    Label(dataUsage.formatBytes(selectedDay.wifiBytes), systemImage: "wifi")
                        .foregroundStyle(wifiColor)
                    Label(dataUsage.formatBytes(selectedDay.cellularBytes), systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(cellularColor)
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .padding(18)
        .usageCardStyle()
    }

    private var monthlySummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Aylik Ozet")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            summaryRow(title: "Bu ay WiFi", value: dataUsage.formatBytes(monthlySummary.wifi), color: wifiColor)
            summaryRow(title: "Bu ay Cellular", value: dataUsage.formatBytes(monthlySummary.cellular), color: cellularColor)
            summaryRow(title: "Gunluk ortalama", value: dataUsage.formatBytes(monthlySummary.dailyAverage), color: .white)
            summaryRow(title: "Tahmini aylik toplam", value: dataUsage.formatBytes(monthlySummary.projectedMonthly), color: .white)
        }
        .padding(18)
        .usageCardStyle()
    }

    private var resetInfoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sifirlama Bilgisi")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Sayac \(dataUsage.daysUntilReset(resetDay: dataLimitResetDay)) gun sonra sifirlanacak")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))

            Button {
                showingResetAlert = true
            } label: {
                Text("Sifirla")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .padding(18)
        .usageCardStyle()
    }

    private var placeholderCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white.opacity(0.7))
                .scaleEffect(1.2)
            Text("Veri toplaniyor...")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .padding(18)
        .usageCardStyle()
    }

    private var limitMessage: String {
        let usedGB = Double(todayTotal) / (1024 * 1024 * 1024)
        return String(format: "%.1f GB limitin %.1f GB'ini kullandin", dataLimitGB, usedGB)
    }

    private func usageRow(title: String, value: String, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Text(value)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
    }

    private func summaryRow(title: String, value: String, color: Color) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.white.opacity(0.68))
            Spacer()
            Text(value)
                .foregroundStyle(color)
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
    }

    private func weekdayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func axisLabel(_ bytes: Double) -> String {
        let gb = bytes / (1024 * 1024 * 1024)
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        return String(format: "%.0f MB", bytes / (1024 * 1024))
    }

    private func nearestDay(to date: Date) -> DailyUsageSample? {
        weeklySamples.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }
}

private struct UsageCardModifier: ViewModifier {
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
    func usageCardStyle() -> some View {
        modifier(UsageCardModifier())
    }
}

#Preview {
    UsageView(dataUsage: DataUsageMonitor())
}
