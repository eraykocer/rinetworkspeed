//
//  ISPReportGenerator.swift
//  rinetworkspeed
//
//  Printable PDF that compares measured speeds with the advertised plan, for
//  sending to an internet provider. White background on purpose: it is meant
//  to be printed or attached to a complaint, unlike the dark usage report.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ISPReportGenerator {
    private let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4 at 72 dpi
    private let margin: CGFloat = 40

    private let ink = UIColor(white: 0.1, alpha: 1)
    private let muted = UIColor(white: 0.45, alpha: 1)
    private let rule = UIColor(white: 0.85, alpha: 1)
    private let good = UIColor(red: 0.10, green: 0.55, blue: 0.30, alpha: 1)
    private let bad = UIColor(red: 0.78, green: 0.16, blue: 0.16, alpha: 1)

    func makePDF(plan: InternetPlan, results: [SpeedTestResult]) -> Data {
        let sorted = results.sorted { $0.date < $1.date }
        let comparison = PlanComparison(plan: plan, results: sorted)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            var page = 1
            context.beginPage()
            var y = drawHeader(plan: plan, results: sorted)
            if let comparison {
                y = drawSummary(comparison, top: y)
            }
            y = drawTableHeader(top: y + 16)

            for result in sorted {
                if y > pageRect.height - margin - 40 {
                    drawFooter(page: page)
                    page += 1
                    context.beginPage()
                    y = drawTableHeader(top: margin)
                }
                y = drawRow(result, comparison: comparison, top: y)
            }
            drawFooter(page: page)
        }
    }

    // MARK: Sections

    private func drawHeader(plan: InternetPlan, results: [SpeedTestResult]) -> CGFloat {
        var y = margin
        y = text(String(localized: "Internet Speed Report"), at: y, font: .systemFont(ofSize: 22, weight: .bold))

        let provider = plan.provider.isEmpty ? String(localized: "Not specified") : plan.provider
        y = text(String(localized: "Provider: \(provider)"), at: y + 6, font: .systemFont(ofSize: 12), color: muted)

        var advertised = String(localized: "Advertised download: \(plan.downloadMbps.fixed(0)) Mbps")
        if plan.uploadMbps > 0 {
            advertised += " · " + String(localized: "Advertised upload: \(plan.uploadMbps.fixed(0)) Mbps")
        }
        y = text(advertised, at: y + 2, font: .systemFont(ofSize: 12), color: muted)

        if let first = results.first?.date, let last = results.last?.date {
            let range = "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))"
            y = text(String(localized: "Period: \(range)"), at: y + 2, font: .systemFont(ofSize: 12), color: muted)
        }
        y = text(String(localized: "Generated: \(Date().formatted(date: .abbreviated, time: .shortened))"), at: y + 2, font: .systemFont(ofSize: 12), color: muted)
        return line(at: y + 12)
    }

    private func drawSummary(_ c: PlanComparison, top: CGFloat) -> CGFloat {
        var y = text(String(localized: "Summary"), at: top + 12, font: .systemFont(ofSize: 15, weight: .semibold))

        let percent: (Double) -> String = { $0.formatted(.percent.precision(.fractionLength(0))) }
        var rows: [(String, String)] = [
            (String(localized: "Tests"), "\(c.testCount)"),
            (String(localized: "Average download"), String(localized: "\(percent(c.averageDownloadRatio)) of advertised")),
            (String(localized: "Median download"), "\(c.medianDownloadMbps.fixed(1)) Mbps"),
            (String(localized: "Slowest download"), "\(c.minimumDownloadMbps.fixed(1)) Mbps"),
            (String(localized: "Tests reaching 80% of plan"), percent(c.meetsPlanShare)),
            (String(localized: "Tests below 50% of plan"), percent(c.farBelowShare)),
            (String(localized: "Average ping"), "\(c.averagePing.fixed(0)) ms")
        ]
        if let upload = c.averageUploadRatio {
            rows.insert((String(localized: "Average upload"), String(localized: "\(percent(upload)) of advertised")), at: 2)
        }

        for (label, value) in rows {
            let rowTop = y + 4
            _ = text(label, at: rowTop, font: .systemFont(ofSize: 12), color: muted)
            y = text(value, at: rowTop, x: margin + 260, font: .systemFont(ofSize: 12, weight: .semibold))
        }

        let verdict: String
        let color: UIColor
        if c.meetsPlanShare >= 0.8 {
            verdict = String(localized: "Measured speeds are consistent with the advertised plan.")
            color = good
        } else if c.averageDownloadRatio >= PlanComparison.meetsThreshold {
            verdict = String(localized: "Average speed meets the plan, but some tests fall well short of it.")
            color = muted
        } else {
            verdict = String(localized: "Measured speeds are consistently below the advertised plan.")
            color = bad
        }
        y = text(verdict, at: y + 10, font: .systemFont(ofSize: 12, weight: .semibold), color: color)

        let method = String(localized: "Each test downloads and uploads data over several parallel connections to Cloudflare's speed test servers for about 20 seconds. The first 2 seconds of each phase are excluded. Wi-Fi signal, other devices on the network and the server location can lower results.")
        y = paragraph(method, top: y + 8)
        return line(at: y + 12)
    }

    private let columns: [CGFloat] = [40, 165, 300, 370, 440, 495]

    private func drawTableHeader(top: CGFloat) -> CGFloat {
        let titles = [
            String(localized: "Date"), String(localized: "Network"), String(localized: "Download"),
            String(localized: "Upload"), String(localized: "Ping"), String(localized: "% of plan")
        ]
        for (index, title) in titles.enumerated() {
            _ = text(title, at: top, x: columns[index], font: .systemFont(ofSize: 10, weight: .semibold), color: muted)
        }
        return line(at: top + 16) + 4
    }

    private func drawRow(_ result: SpeedTestResult, comparison: PlanComparison?, top: CGFloat) -> CGFloat {
        let score = result.score
        let font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let network = result.ssid ?? result.connection.map { String(localized: $0.title) } ?? "–"

        _ = text(result.date.formatted(date: .numeric, time: .shortened), at: top, x: columns[0], font: font)
        _ = text(network, at: top, x: columns[1], width: columns[2] - columns[1] - 8, font: font)
        _ = text("\(score.downloadMbps.fixed(1))", at: top, x: columns[2], font: font)
        _ = text("\(score.uploadMbps.fixed(1))", at: top, x: columns[3], font: font)
        _ = text("\(result.ping.fixed(0))", at: top, x: columns[4], font: font)

        if let comparison {
            let ratio = comparison.downloadRatio(of: result)
            let color = ratio >= PlanComparison.meetsThreshold ? good : (ratio < PlanComparison.farBelowThreshold ? bad : ink)
            _ = text(ratio.formatted(.percent.precision(.fractionLength(0))), at: top, x: columns[5], font: font, color: color)
        }
        return top + 16
    }

    private func drawFooter(page: Int) {
        let footer = "RiNetwork · " + String(localized: "Page \(page)")
        _ = text(footer, at: pageRect.height - margin + 10, font: .systemFont(ofSize: 9), color: muted)
    }

    // MARK: Drawing helpers

    /// Draws single-line text and returns the y below it.
    @discardableResult
    private func text(_ string: String, at y: CGFloat, x: CGFloat? = nil, width: CGFloat? = nil, font: UIFont, color: UIColor? = nil) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color ?? ink]
        let originX = x ?? margin
        let rect = CGRect(x: originX, y: y, width: width ?? (pageRect.width - originX - margin), height: font.lineHeight + 2)
        (string as NSString).draw(with: rect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: attributes, context: nil)
        return y + font.lineHeight
    }

    /// Draws wrapped text across the content width and returns the y below it.
    private func paragraph(_ string: String, top: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: muted]
        let width = pageRect.width - margin * 2
        let bounds = (string as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
        (string as NSString).draw(with: CGRect(x: margin, y: top, width: width, height: bounds.height), options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
        return top + bounds.height
    }

    private func line(at y: CGFloat) -> CGFloat {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
        rule.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        return y
    }
}

/// Builds the PDF only when the user shares it.
struct ISPReportExport: Transferable {
    let plan: InternetPlan
    let results: [SpeedTestResult]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { export in
            await MainActor.run {
                ISPReportGenerator().makePDF(plan: export.plan, results: export.results)
            }
        }
        .suggestedFileName("Internet-Speed-Report.pdf")
    }
}
