//
//  UsageView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Charts
import UIKit

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
    @ObservedObject var speedTestManager: SpeedTestManager
    @AppStorage("dataLimitEnabled") private var dataLimitEnabled: Bool = false
    @AppStorage("dataLimitGB") private var dataLimitGB: Double = 5.0
    @AppStorage("dataLimitResetDay") private var dataLimitResetDay: Int = 1

    @State private var selectedDay: DailyUsageSample?
    @State private var showingResetAlert = false
    @State private var showPDFSheet = false
    @State private var selectedReportMonth: Date = Date()
    @State private var isGeneratingPDF = false

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
                        pdfReportCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Data Usage")
            .alert("Reset today's counter?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    dataUsage.resetToday()
                }
            } message: {
                Text("Today's WiFi and Cellular counters will be reset.")
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

                    Text("Today's Total")
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
            Text("Weekly Chart")
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
            Text("Monthly Summary")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            summaryRow(title: "This month WiFi", value: dataUsage.formatBytes(monthlySummary.wifi), color: wifiColor)
            summaryRow(title: "This month Cellular", value: dataUsage.formatBytes(monthlySummary.cellular), color: cellularColor)
            summaryRow(title: "Daily average", value: dataUsage.formatBytes(monthlySummary.dailyAverage), color: .white)
            summaryRow(title: "Projected monthly total", value: dataUsage.formatBytes(monthlySummary.projectedMonthly), color: .white)
        }
        .padding(18)
        .usageCardStyle()
    }

    private var resetInfoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reset Info")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Counter resets in \(dataUsage.daysUntilReset(resetDay: dataLimitResetDay)) days")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))

            Button {
                showingResetAlert = true
            } label: {
                Text("Reset")
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

    // MARK: – PDF Report Card

    private var last6Months: [Date] {
        let cal = Calendar.current
        return (0..<6).compactMap { cal.date(byAdding: .month, value: -$0, to: Date()) }
    }

    private var pdfReportCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(red: 59/255, green: 130/255, blue: 246/255))
                Text("PDF Report")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            // Month picker
            Picker("Ay", selection: $selectedReportMonth) {
                ForEach(last6Months, id: \.self) { date in
                    Text(date.formatted(.dateTime.month(.wide).year()))
                        .tag(date)
                }
            }
            .pickerStyle(.menu)
            .tint(Color(red: 59/255, green: 130/255, blue: 246/255))
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )

            // Generate button
            Button {
                generatePDFReport()
            } label: {
                HStack(spacing: 10) {
                    if isGeneratingPDF {
                        ProgressView().tint(.white).scaleEffect(0.9)
                    } else {
                        Image(systemName: "arrow.down.doc.fill")
                    }
                    Text(isGeneratingPDF ? "Generating..." : "Generate Report")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 59/255,  green: 130/255, blue: 246/255),
                                    Color(red: 168/255, green: 85/255,  blue: 247/255)
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingPDF)
        }
        .padding(18)
        .usageCardStyle()
    }

    private func generatePDFReport() {
        isGeneratingPDF = true
        Task {
            let samples = dataUsage.usageForMonth(selectedReportMonth)
            let history = speedTestManager.history
            let generator = PDFReportGenerator()
            let url = generator.generateReport(
                month: selectedReportMonth,
                dailySamples: samples,
                speedHistory: history,
                formatBytes: dataUsage.formatBytes
            )
            isGeneratingPDF = false
            guard let url else { return }
            presentShare(items: [url])
        }
    }

    private func presentShare(items: [Any]) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        rootVC.present(activityVC, animated: true)
    }

    private var placeholderCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white.opacity(0.7))
                .scaleEffect(1.2)
            Text("Collecting data...")
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
        return String(format: "Used %.1f GB of your %.1f GB limit", usedGB, dataLimitGB)
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
        formatter.locale = Locale(identifier: "en_US_POSIX")
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
    UsageView(dataUsage: DataUsageMonitor(), speedTestManager: SpeedTestManager())
}
