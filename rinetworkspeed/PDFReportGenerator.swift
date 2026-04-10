//
//  PDFReportGenerator.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import UIKit
import PDFKit
import SwiftUI
import Charts

// MARK: - PDF Chart view (rendered via ImageRenderer)

private struct PDFUsageChartView: View {
    struct ChartBar: Identifiable {
        let id = UUID()
        let date: Date
        let type: String
        let bytes: UInt64
    }

    let samples: [DailyUsageSample]

    private var bars: [ChartBar] {
        samples.flatMap {
            [
                ChartBar(date: $0.date, type: "WiFi",     bytes: $0.wifiBytes),
                ChartBar(date: $0.date, type: "Cellular", bytes: $0.cellularBytes)
            ]
        }
    }

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Date", bar.date, unit: .day),
                y: .value("Bytes", bar.bytes)
            )
            .position(by: .value("Type", bar.type))
            .foregroundStyle(by: .value("Type", bar.type))
        }
        .chartForegroundStyleScale([
            "WiFi":     Color(red: 59/255,  green: 130/255, blue: 246/255),
            "Cellular": Color(red: 249/255, green: 115/255, blue: 22/255)
        ])
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.caption2)
                    }
                }
                .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let bytes = value.as(Double.self) {
                        Text(shortBytesLabel(bytes))
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
            }
        }
        .chartLegend(position: .top, alignment: .leading, spacing: 8)
        .padding(16)
        .background(Color(red: 12/255, green: 12/255, blue: 30/255))
        .frame(width: 480, height: 280)
    }

    private func shortBytesLabel(_ bytes: Double) -> String {
        let gb = bytes / (1024 * 1024 * 1024)
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = bytes / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Generator

@MainActor
final class PDFReportGenerator {

    // A4 page in points
    private let pageW: CGFloat = 595
    private let pageH: CGFloat = 842
    private let margin: CGFloat = 48

    // UIKit colours (used for CoreGraphics / NSString drawing)
    private let darkBg     = UIColor(red: 8/255,   green: 8/255,   blue: 20/255,  alpha: 1)
    private let accentBlue = UIColor(red: 59/255,  green: 130/255, blue: 246/255, alpha: 1)
    private let accentPurp = UIColor(red: 168/255, green: 85/255,  blue: 247/255, alpha: 1)
    private let accentOra  = UIColor(red: 249/255, green: 115/255, blue: 22/255,  alpha: 1)
    private let white      = UIColor.white
    private let dimWhite   = UIColor.white.withAlphaComponent(0.52)

    // MARK: Public API

    func generateReport(
        month: Date,
        dailySamples: [DailyUsageSample],
        speedHistory: [SpeedTestResult],
        formatBytes: @escaping (UInt64) -> String
    ) -> URL? {
        let chartImage = renderChartImage(samples: dailySamples)

        let pageRect = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { ctx in
            // Page 1 – Cover
            ctx.beginPage()
            drawCoverPage(ctx.cgContext, month: month, samples: dailySamples, formatBytes: formatBytes)

            // Page 2 – Daily usage table
            ctx.beginPage()
            drawDailyUsagePage(ctx.cgContext, samples: dailySamples, formatBytes: formatBytes, pageNumber: 2)

            // Page 3 – Speed test history
            ctx.beginPage()
            drawSpeedHistoryPage(ctx.cgContext, history: speedHistory, pageNumber: 3)

            // Page 4 – Chart
            ctx.beginPage()
            drawChartPage(ctx.cgContext, chartImage: chartImage, samples: dailySamples, formatBytes: formatBytes, pageNumber: 4)
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy_MM"
        let fileName = "NetworkSpeed_\(fmt.string(from: month)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Chart image

    private func renderChartImage(samples: [DailyUsageSample]) -> UIImage? {
        let view = PDFUsageChartView(samples: samples)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.uiImage
    }

    // MARK: – Page 1: Cover

    private func drawCoverPage(
        _ ctx: CGContext, month: Date,
        samples: [DailyUsageSample],
        formatBytes: (UInt64) -> String
    ) {
        fillBackground(ctx)
        drawGradientOverlay(ctx)
        drawHeader(ctx, title: "NetworkSpeed", pageNumber: 1)

        // Title block
        centeredText(ctx, "NetworkSpeed",
                     font: .systemFont(ofSize: 30, weight: .bold), color: white, y: 130)
        centeredText(ctx, "Monthly Usage Report",
                     font: .systemFont(ofSize: 16, weight: .medium), color: dimWhite, y: 172)

        let mf = DateFormatter(); mf.dateFormat = "MMMM yyyy"
        centeredText(ctx, mf.string(from: month),
                     font: .systemFont(ofSize: 26, weight: .bold), color: accentBlue, y: 216)

        // Separator
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.07).cgColor)
        ctx.fill(CGRect(x: margin, y: 268, width: pageW - margin * 2, height: 1))

        // Stat boxes
        let wifi     = samples.reduce(0) { $0 + $1.wifiBytes }
        let cellular = samples.reduce(0) { $0 + $1.cellularBytes }
        let activeDays = samples.filter { $0.wifiBytes + $0.cellularBytes > 0 }.count
        let avgDaily: UInt64 = activeDays > 0 ? (wifi + cellular) / UInt64(activeDays) : 0

        let half = (pageW - margin * 2 - 16) / 2
        statBox(ctx, x: margin,          y: 300, w: half, label: "Total Used",      value: formatBytes(wifi + cellular), accent: accentBlue)
        statBox(ctx, x: margin + half + 16, y: 300, w: half, label: "Days Tracked", value: "\(activeDays)",              accent: accentPurp)
        statBox(ctx, x: margin,          y: 408, w: half, label: "WiFi",            value: formatBytes(wifi),            accent: accentBlue)
        statBox(ctx, x: margin + half + 16, y: 408, w: half, label: "Cellular",     value: formatBytes(cellular),        accent: accentOra)
        statBox(ctx, x: margin,          y: 516, w: pageW - margin * 2, label: "Daily Average", value: formatBytes(avgDaily), accent: accentPurp)

        drawFooter(ctx, pageNumber: 1)
    }

    // MARK: – Page 2: Daily usage table

    private func drawDailyUsagePage(
        _ ctx: CGContext, samples: [DailyUsageSample],
        formatBytes: (UInt64) -> String, pageNumber: Int
    ) {
        fillBackground(ctx)
        drawHeader(ctx, title: "Daily Data Usage", pageNumber: pageNumber)

        let df = DateFormatter(); df.dateFormat = "dd MMM"
        let cols: [CGFloat] = [margin, margin + 100, margin + 240, margin + 360, margin + 470]
        let rowH: CGFloat  = 26
        let startY: CGFloat = 70

        // Table header
        tableHeaderRow(ctx, y: startY, rowH: rowH,
                       cols: cols, titles: ["Date", "WiFi", "Cellular", "Total", ""])

        let cellFont = UIFont.systemFont(ofSize: 10.5, weight: .medium)

        for (i, sample) in samples.enumerated() {
            let y = startY + rowH + CGFloat(i) * rowH
            if y + rowH > pageH - 50 { break }     // respect footer

            if i.isMultiple(of: 2) {
                ctx.setFillColor(UIColor.white.withAlphaComponent(0.03).cgColor)
                ctx.fill(CGRect(x: margin, y: y, width: pageW - margin * 2, height: rowH))
            }

            let total = sample.wifiBytes + sample.cellularBytes
            at(ctx, df.string(from: sample.date),      font: cellFont, color: white,       pt: CGPoint(x: cols[0] + 6, y: y + 7))
            at(ctx, formatBytes(sample.wifiBytes),     font: cellFont, color: accentBlue,  pt: CGPoint(x: cols[1] + 6, y: y + 7))
            at(ctx, formatBytes(sample.cellularBytes), font: cellFont, color: accentOra,   pt: CGPoint(x: cols[2] + 6, y: y + 7))
            at(ctx, formatBytes(total),                font: cellFont, color: white,       pt: CGPoint(x: cols[3] + 6, y: y + 7))
        }

        drawFooter(ctx, pageNumber: pageNumber)
    }

    // MARK: – Page 3: Speed history

    private func drawSpeedHistoryPage(
        _ ctx: CGContext, history: [SpeedTestResult], pageNumber: Int
    ) {
        fillBackground(ctx)
        drawHeader(ctx, title: "Speed Test History", pageNumber: pageNumber)

        let df = DateFormatter(); df.dateFormat = "dd.MM.yy HH:mm"
        let cols: [CGFloat] = [margin, margin + 115, margin + 225, margin + 335, margin + 420]
        let rowH: CGFloat   = 26
        let startY: CGFloat = 70

        tableHeaderRow(ctx, y: startY, rowH: rowH,
                       cols: cols, titles: ["Date", "Download", "Upload", "Ping", "Grade"])

        let cellFont = UIFont.systemFont(ofSize: 10, weight: .medium)

        for (i, result) in history.prefix(25).enumerated() {
            let y = startY + rowH + CGFloat(i) * rowH
            if y + rowH > pageH - 50 { break }

            if i.isMultiple(of: 2) {
                ctx.setFillColor(UIColor.white.withAlphaComponent(0.03).cgColor)
                ctx.fill(CGRect(x: margin, y: y, width: pageW - margin * 2, height: rowH))
            }

            let dl = result.downloadSpeed / (1024 * 1024)
            let ul = result.uploadSpeed   / (1024 * 1024)
            let gr = grade(download: dl, upload: ul, ping: result.ping)

            at(ctx, df.string(from: result.date),    font: cellFont, color: white,              pt: CGPoint(x: cols[0] + 6, y: y + 7))
            at(ctx, String(format: "%.1f MB/s", dl), font: cellFont, color: accentBlue,         pt: CGPoint(x: cols[1] + 6, y: y + 7))
            at(ctx, String(format: "%.1f MB/s", ul), font: cellFont, color: accentPurp,         pt: CGPoint(x: cols[2] + 6, y: y + 7))
            at(ctx, String(format: "%.0f ms", result.ping), font: cellFont, color: accentOra,   pt: CGPoint(x: cols[3] + 6, y: y + 7))
            at(ctx, gr,                              font: .systemFont(ofSize: 12, weight: .bold),
                                                     color: gradeColor(gr),                      pt: CGPoint(x: cols[4] + 6, y: y + 6))
        }

        drawFooter(ctx, pageNumber: pageNumber)
    }

    // MARK: – Page 4: Chart

    private func drawChartPage(
        _ ctx: CGContext, chartImage: UIImage?,
        samples: [DailyUsageSample],
        formatBytes: (UInt64) -> String,
        pageNumber: Int
    ) {
        fillBackground(ctx)
        drawHeader(ctx, title: "Usage Chart", pageNumber: pageNumber)

        if let image = chartImage {
            let imgRect = CGRect(x: margin, y: 80, width: pageW - margin * 2, height: 320)
            image.draw(in: imgRect)
        }

        // Totals summary below chart
        let wifi     = samples.reduce(0) { $0 + $1.wifiBytes }
        let cellular = samples.reduce(0) { $0 + $1.cellularBytes }
        let summaryFont = UIFont.systemFont(ofSize: 12, weight: .medium)
        at(ctx, "WiFi: \(formatBytes(wifi))",
           font: summaryFont, color: accentBlue, pt: CGPoint(x: margin, y: 420))
        at(ctx, "Cellular: \(formatBytes(cellular))",
           font: summaryFont, color: accentOra,  pt: CGPoint(x: margin, y: 440))
        at(ctx, "Total: \(formatBytes(wifi + cellular))",
           font: UIFont.systemFont(ofSize: 12, weight: .bold), color: white,
           pt: CGPoint(x: margin, y: 460))

        drawFooter(ctx, pageNumber: pageNumber)
    }

    // MARK: – Draw helpers

    private func fillBackground(_ ctx: CGContext) {
        ctx.setFillColor(darkBg.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pageW, height: pageH))
    }

    private func drawGradientOverlay(_ ctx: CGContext) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            UIColor(red: 10/255, green: 20/255, blue: 60/255, alpha: 0.55).cgColor,
            UIColor(red: 55/255, green: 10/255, blue: 80/255, alpha: 0.35).cgColor
        ] as CFArray
        let locs: [CGFloat] = [0, 1]
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locs) else { return }
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: 0),
                               end:   CGPoint(x: pageW, y: pageH),
                               options: [])
    }

    private func drawHeader(_ ctx: CGContext, title: String, pageNumber: Int) {
        // Header bar
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.05).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pageW, height: 44))
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.08).cgColor)
        ctx.fill(CGRect(x: 0, y: 43, width: pageW, height: 1))

        at(ctx, "NetworkSpeed", font: .systemFont(ofSize: 12, weight: .bold),   color: white,    pt: CGPoint(x: margin, y: 13))
        at(ctx, title,          font: .systemFont(ofSize: 11, weight: .medium),  color: dimWhite, pt: CGPoint(x: margin + 120, y: 14))

        let dateStr = Date().formatted(date: .abbreviated, time: .omitted)
        let headerRight = "Generated: \(dateStr)"
        let rW = textWidth(headerRight, font: .systemFont(ofSize: 10, weight: .medium))
        at(ctx, headerRight, font: .systemFont(ofSize: 10, weight: .medium), color: dimWhite,
           pt: CGPoint(x: pageW - margin - rW, y: 15))
    }

    private func drawFooter(_ ctx: CGContext, pageNumber: Int) {
        let y = pageH - 32
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.07).cgColor)
        ctx.fill(CGRect(x: 0, y: y, width: pageW, height: 1))

        at(ctx, "NetworkSpeed App", font: .systemFont(ofSize: 9, weight: .medium), color: dimWhite,
           pt: CGPoint(x: margin, y: y + 9))
        let pg = "Page \(pageNumber) / 4"
        let pgW = textWidth(pg, font: .systemFont(ofSize: 9, weight: .medium))
        at(ctx, pg, font: .systemFont(ofSize: 9, weight: .medium), color: dimWhite,
           pt: CGPoint(x: pageW - margin - pgW, y: y + 9))
    }

    private func statBox(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, label: String, value: String, accent: UIColor) {
        let h: CGFloat = 92
        let rect = CGRect(x: x, y: y, width: w, height: h)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        ctx.setFillColor(accent.withAlphaComponent(0.08).cgColor)
        ctx.addPath(path.cgPath); ctx.fillPath()
        ctx.setStrokeColor(accent.withAlphaComponent(0.22).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path.cgPath); ctx.strokePath()

        at(ctx, label,
           font: .systemFont(ofSize: 10.5, weight: .medium), color: dimWhite,
           pt: CGPoint(x: x + 14, y: y + 14))
        at(ctx, value,
           font: .systemFont(ofSize: 20, weight: .bold), color: white,
           pt: CGPoint(x: x + 14, y: y + 38))
    }

    private func tableHeaderRow(
        _ ctx: CGContext, y: CGFloat, rowH: CGFloat,
        cols: [CGFloat], titles: [String]
    ) {
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.09).cgColor)
        ctx.fill(CGRect(x: margin, y: y, width: pageW - margin * 2, height: rowH))

        let hf = UIFont.systemFont(ofSize: 10.5, weight: .bold)
        for (i, title) in titles.enumerated() where i < cols.count {
            at(ctx, title, font: hf, color: dimWhite, pt: CGPoint(x: cols[i] + 6, y: y + 7))
        }
    }

    private func centeredText(_ ctx: CGContext, _ text: String, font: UIFont, color: UIColor, y: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let w = (text as NSString).size(withAttributes: attrs).width
        (text as NSString).draw(at: CGPoint(x: (pageW - w) / 2, y: y), withAttributes: attrs)
    }

    private func at(_ ctx: CGContext, _ text: String, font: UIFont, color: UIColor, pt: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: pt, withAttributes: attrs)
    }

    private func textWidth(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    // MARK: – Grade helpers

    private func grade(download: Double, upload: Double, ping: Double) -> String {
        if ping < 20, download > 60, upload > 25 { return "A" }
        if ping < 35, download > 30, upload > 12 { return "B" }
        if ping < 60, download > 15, upload > 6  { return "C" }
        if ping < 90, download > 5,  upload > 2  { return "D" }
        return "F"
    }

    private func gradeColor(_ grade: String) -> UIColor {
        switch grade {
        case "A": return UIColor(red: 52/255,  green: 211/255, blue: 153/255, alpha: 1)
        case "B": return UIColor(red: 59/255,  green: 130/255, blue: 246/255, alpha: 1)
        case "C": return UIColor(red: 234/255, green: 179/255, blue: 8/255,   alpha: 1)
        case "D": return UIColor(red: 249/255, green: 115/255, blue: 22/255,  alpha: 1)
        default:  return UIColor(red: 239/255, green: 68/255,  blue: 68/255,  alpha: 1)
        }
    }
}
