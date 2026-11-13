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
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    /// Only read when generating the PDF report; not observed to avoid re-rendering during speed tests.
    let speedTestManager: SpeedTestManager
    @AppStorage("dataLimitEnabled") private var dataLimitEnabled: Bool = false
    @AppStorage("dataLimitGB") private var dataLimitGB: Double = 5.0
    @AppStorage("dataLimitResetDay") private var dataLimitResetDay: Int = 1

    @State private var selectedDay: DailyUsageSample?
    @State private var showingResetAlert = false
    @State private var showPDFSheet = false
    @State private var selectedReportMonth: Date = Date()
    @State private var isGeneratingPDF = false

    // Swift Charts shows series values verbatim in the legend, so they are localized here.
    private static let wifiSeries = String(localized: "Wi-Fi")
    private static let cellularSeries = String(localized: "Cellular")

    private let wifiColor = AppTheme.download
    private let cellularColor = AppTheme.upload

    private var todayTotal: UInt64 {
        dataUsage.todayWifiBytes + dataUsage.todayCellularBytes
    }

    private var weeklySamples: [DailyUsageSample] {
        dataUsage.usageForLast7Days()
    }

    private var monthlySummary: (wifi: UInt64, cellular: UInt64, dailyAverage: UInt64, projectedMonthly: UInt64) {
        dataUsage.monthlySummary()
    }

    private var limitBytes: Double {
        dataLimitGB * 1024 * 1024 * 1024
    }

    /// With a data limit the ring shows cellular usage in the current billing
    /// period against the limit (a carrier plan is monthly and cellular-only);
    /// without one it compares today against the 7-day daily average.
    private var progressTarget: Double {
        if dataLimitEnabled {
            return max(limitBytes, 1)
        }

        let weeklyTotal = Double(dataUsage.weeklyWifiBytes + dataUsage.weeklyCellularBytes)
        let average = weeklyTotal > 0 ? weeklyTotal / 7 : Double(max(todayTotal, 1))
        return max(average, 1)
    }

    private var progressValue: Double {
        dataLimitEnabled ? Double(dataUsage.periodCellularBytes) : Double(todayTotal)
    }

    private var ringProgress: Double {
        min(1, progressValue / progressTarget)
    }

    private var chartBars: [UsageChartBar] {
        weeklySamples.flatMap { sample in
            let isToday = Calendar.current.isDateInToday(sample.date)
            return [
                UsageChartBar(date: sample.date, label: weekdayLabel(for: sample.date), type: Self.wifiSeries, bytes: sample.wifiBytes, isToday: isToday),
                UsageChartBar(date: sample.date, label: weekdayLabel(for: sample.date), type: Self.cellularSeries, bytes: sample.cellularBytes, isToday: isToday)
            ]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    if !dataUsage.hasInitialSample {
                        placeholderCard
                    } else {
                        heroCard
                        weeklyChartCard
                        monthlySummaryCard
                        resetInfoCard
                        pdfReportCard
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .appPageBackground()
            .navigationTitle("Data Usage")
            .onChange(of: dataLimitResetDay) { _, _ in
                dataUsage.recalculatePeriodTotals()
            }
            .alert("Reset today's counter?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    dataUsage.resetToday()
                }
            } message: {
                Text("Today's WiFi and Cellular counters will be reset.")
            }
        }
        .appPageBackground()
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        let isOverLimit = self.isOverLimit
        let ringColor = isOverLimit ? AppTheme.danger : wifiColor

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today's Total")
                        .appFont(size: 13, weight: .semibold, design: .rounded)
                        .foregroundStyle(AppTheme.secondaryText)
                        .textCase(.uppercase)

                    Text(dataUsage.formatBytes(todayTotal))
                        .appFont(size: 40, weight: .bold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())

                    if dataLimitEnabled {
                        Text(limitMessage)
                            .appFont(size: 13, weight: .medium, design: .rounded)
                            .foregroundStyle(isOverLimit ? AppTheme.danger : AppTheme.secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 12)

                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .stroke(AppTheme.ink.opacity(0.08), style: StrokeStyle(lineWidth: 8, lineCap: .round))

                        Circle()
                            .trim(from: 0, to: ringProgress)
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.35), value: ringProgress)

                        if isOverLimit {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .appFont(size: 20, weight: .bold)
                                .foregroundStyle(AppTheme.danger)
                        } else {
                            Text(ringProgress, format: .percent.precision(.fractionLength(0)))
                                .appFont(size: 15, weight: .bold, design: .rounded)
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.primaryText)
                                .contentTransition(.numericText())
                        }
                    }
                    .frame(width: 72, height: 72)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(dataLimitEnabled ? Text("Cellular data limit used") : Text("Today compared with your daily average"))
                    .accessibilityValue(Text(ringProgress, format: .percent.precision(.fractionLength(0))))

                    Text(dataLimitEnabled ? "of limit" : "of daily avg")
                        .appFont(size: 11, weight: .medium, design: .rounded)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }

            UsageSplitBar(
                wifiBytes: dataUsage.todayWifiBytes,
                cellularBytes: dataUsage.todayCellularBytes,
                wifiColor: wifiColor,
                cellularColor: cellularColor
            )

            AppAdaptiveStack(spacing: 12) {
                UsageHeroMetric(
                    icon: "wifi",
                    caption: "WiFi",
                    value: dataUsage.formatBytes(dataUsage.todayWifiBytes),
                    tint: wifiColor
                )
                UsageHeroMetric(
                    icon: "antenna.radiowaves.left.and.right",
                    caption: "Cellular",
                    value: dataUsage.formatBytes(dataUsage.todayCellularBytes),
                    tint: cellularColor
                )
            }
        }
        .appCard(padding: 20)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.danger.opacity(isOverLimit ? 0.6 : 0), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.35), value: isOverLimit)
    }

    // MARK: - Weekly Chart

    private var weeklyChartCard: some View {
        AppSection("Weekly Chart") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    legendItem(title: "WiFi", color: wifiColor)
                    legendItem(title: "Cellular", color: cellularColor)
                    Spacer()
                }

                Chart(chartBars) { bar in
                    BarMark(
                        x: .value("Day", bar.date, unit: .day),
                        y: .value("Usage", bar.bytes)
                    )
                    .position(by: .value("Type", bar.type))
                    .foregroundStyle(by: .value("Type", bar.type))
                    .cornerRadius(4)
                    .opacity(bar.isToday ? 1 : 0.76)
                    .annotation(position: .top, spacing: 4) {
                        if bar.isToday && selectedDay == nil {
                            Capsule()
                                .fill(AppTheme.ink.opacity(0.18))
                                .frame(width: 24, height: 3)
                        }
                    }
                }
                .chartForegroundStyleScale([
                    Self.wifiSeries: wifiColor,
                    Self.cellularSeries: cellularColor
                ])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(weekdayLabel(for: date))
                            }
                        }
                        .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(AppTheme.separator)
                        AxisValueLabel {
                            if let bytes = value.as(Double.self) {
                                Text(axisLabel(bytes))
                            }
                        }
                        .foregroundStyle(AppTheme.secondaryText)
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
                    HStack(spacing: 16) {
                        Text(selectedDay.date.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer(minLength: 0)
                        Label(dataUsage.formatBytes(selectedDay.wifiBytes), systemImage: "wifi")
                            .foregroundStyle(wifiColor)
                        Label(dataUsage.formatBytes(selectedDay.cellularBytes), systemImage: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(cellularColor)
                    }
                    .appFont(size: 13, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(16)
        }
    }

    // MARK: - Monthly Summary

    private var monthlySummaryCard: some View {
        // Computed once per render; it sorts the whole daily history.
        let monthlySummary = self.monthlySummary
        return AppSection("Monthly Summary") {
            AppRow(icon: "wifi", tint: wifiColor, title: "This month WiFi") {
                valueText(dataUsage.formatBytes(monthlySummary.wifi))
            }
            AppRowDivider()
            AppRow(icon: "antenna.radiowaves.left.and.right", tint: cellularColor, title: "This month Cellular") {
                valueText(dataUsage.formatBytes(monthlySummary.cellular))
            }
            AppRowDivider()
            AppRow(icon: "chart.bar.fill", tint: AppTheme.accent, title: "Daily average") {
                valueText(dataUsage.formatBytes(monthlySummary.dailyAverage))
            }
            AppRowDivider()
            AppRow(icon: "chart.line.uptrend.xyaxis", tint: AppTheme.ping, title: "Projected monthly total") {
                valueText(dataUsage.formatBytes(monthlySummary.projectedMonthly))
            }
        }
    }

    // MARK: - Reset Info

    private var resetInfoCard: some View {
        AppSection("Reset Info") {
            AppRow(
                icon: "calendar.badge.clock",
                tint: AppTheme.warning,
                title: "Billing period resets in \(dataUsage.daysUntilReset(resetDay: dataLimitResetDay)) days"
            )

            AppRowDivider(leadingInset: 0)

            Button {
                showingResetAlert = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset")
                }
                .appFont(size: 16, weight: .semibold, design: .rounded)
                .foregroundStyle(AppTheme.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(AppRowButtonStyle())
        }
    }

    // MARK: – PDF Report Card

    private var last6Months: [Date] {
        let cal = Calendar.current
        return (0..<6).compactMap { cal.date(byAdding: .month, value: -$0, to: Date()) }
    }

    private var pdfReportCard: some View {
        AppSection("PDF Report") {
            AppRow(icon: "doc.richtext.fill", tint: wifiColor, title: "Report Month") {
                Picker("Month", selection: $selectedReportMonth) {
                    ForEach(last6Months, id: \.self) { date in
                        Text(date.formatted(.dateTime.month(.wide).year()))
                            .tag(date)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(wifiColor)
            }

            AppRowDivider(leadingInset: 0)

            Button {
                generatePDFReport()
            } label: {
                HStack(spacing: 10) {
                    if isGeneratingPDF {
                        ProgressView().tint(AppTheme.ink).scaleEffect(0.9)
                    } else {
                        Image(systemName: "arrow.down.doc.fill")
                    }
                    Text(isGeneratingPDF ? "Generating..." : "Generate Report")
                    if !purchaseManager.isPro {
                        ProBadge()
                    }
                }
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(isGeneratingPDF)
            .proGated(feature: .reports)
            .padding(16)
        }
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
                .tint(AppTheme.ink.opacity(0.7))
                .scaleEffect(1.2)
            Text("Collecting data...")
                .appFont(size: 17, weight: .semibold, design: .rounded)
                .foregroundStyle(AppTheme.ink.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .appCard()
    }

    private var isOverLimit: Bool {
        dataLimitEnabled && Double(dataUsage.periodCellularBytes) > limitBytes
    }

    private var limitMessage: String {
        let usedGB = Double(dataUsage.periodCellularBytes) / (1024 * 1024 * 1024)
        let used = usedGB.formatted(.number.precision(.fractionLength(1)))
        let limit = dataLimitGB.formatted(.number.precision(.fractionLength(1)))
        return String(localized: "Cellular this period: \(used) of \(limit) GB")
    }

    private func legendItem(title: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .appFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .appFont(size: 15, weight: .semibold, design: .rounded)
            .monospacedDigit()
            .foregroundStyle(AppTheme.primaryText)
            .contentTransition(.numericText())
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private func weekdayLabel(for date: Date) -> String {
        Self.weekdayFormatter.string(from: date)
    }

    private func axisLabel(_ bytes: Double) -> String {
        let gb = bytes / (1024 * 1024 * 1024)
        if gb >= 1 {
            return gb.fixed(1) + " GB"
        }
        return (bytes / (1024 * 1024)).fixed(0) + " MB"
    }

    private func nearestDay(to date: Date) -> DailyUsageSample? {
        weeklySamples.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }
}

// MARK: - Hero Metric

/// WiFi / Cellular figure inside the hero card; byte strings already include their unit.
private struct UsageHeroMetric: View {
    let icon: String
    let caption: LocalizedStringKey
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .appFont(size: 14, weight: .semibold)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .appFont(size: 11, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
                    .textCase(.uppercase)

                Text(value)
                    .appFont(size: 16, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Split Bar

/// Horizontal bar showing today's WiFi vs Cellular share.
private struct UsageSplitBar: View {
    let wifiBytes: UInt64
    let cellularBytes: UInt64
    let wifiColor: Color
    let cellularColor: Color

    private var wifiShare: Double {
        let total = Double(wifiBytes) + Double(cellularBytes)
        return total > 0 ? Double(wifiBytes) / total : 0
    }

    var body: some View {
        GeometryReader { proxy in
            let total = wifiBytes + cellularBytes
            HStack(spacing: total > 0 && wifiShare > 0 && wifiShare < 1 ? 3 : 0) {
                if total == 0 {
                    Capsule().fill(AppTheme.ink.opacity(0.08))
                } else {
                    if wifiBytes > 0 {
                        Capsule().fill(wifiColor)
                            .frame(width: max(6, proxy.size.width * wifiShare - 1.5))
                    }
                    if cellularBytes > 0 {
                        Capsule().fill(cellularColor)
                    }
                }
            }
        }
        .frame(height: 8)
        .animation(.easeInOut(duration: 0.35), value: wifiShare)
    }
}

#Preview {
    UsageView(dataUsage: DataUsageMonitor(), speedTestManager: SpeedTestManager())
        .preferredColorScheme(.dark)
}
