//
//  ComplicationController.swift
//  NetworkSpeedWatch
//
//  ClockKit complication data source.
//  Supports: .graphicCircular, .graphicCorner, .graphicBezel
//
//  NOTE: ClockKit is deprecated in watchOS 9+.
//  For new projects targeting watchOS 9+ consider WidgetKit complications instead.
//  These implementations remain fully functional on watchOS 9/10/11 for backwards compatibility.
//

import ClockKit
import WatchKit

final class ComplicationController: NSObject, CLKComplicationDataSource {

    // MARK: - Complication Configuration

    func getComplicationDescriptors(
        handler: @escaping ([CLKComplicationDescriptor]) -> Void
    ) {
        let descriptors = [
            CLKComplicationDescriptor(
                identifier: "networkspeed.circular",
                displayName: "Net Speed",
                supportedFamilies: [.graphicCircular]
            ),
            CLKComplicationDescriptor(
                identifier: "networkspeed.corner",
                displayName: "Net Speed Corner",
                supportedFamilies: [.graphicCorner]
            ),
            CLKComplicationDescriptor(
                identifier: "networkspeed.bezel",
                displayName: "Net Speed Bezel",
                supportedFamilies: [.graphicBezel]
            )
        ]
        handler(descriptors)
    }

    func handleSharedComplicationDescriptors(
        _ complicationDescriptors: [CLKComplicationDescriptor]
    ) {}

    // MARK: - Timeline Configuration

    func getTimelineEndDate(
        for complication: CLKComplication,
        withHandler handler: @escaping (Date?) -> Void
    ) {
        // No end — we serve live data only
        handler(nil)
    }

    func getPrivacyBehavior(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void
    ) {
        handler(.showOnLockScreen)
    }

    // MARK: - Timeline Population

    func getCurrentTimelineEntry(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void
    ) {
        handler(makeEntry(for: complication))
    }

    func getTimelineEntries(
        for complication: CLKComplication,
        after date: Date,
        limit: Int,
        withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void
    ) {
        // Real-time updates via reloadTimeline — no scheduled entries needed
        handler(nil)
    }

    // MARK: - Sample Templates (used in the watch face picker)

    func getLocalizableSampleTemplate(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTemplate?) -> Void
    ) {
        // Sample: 12.5 MB/s down, 3.2 MB/s up
        handler(makeTemplate(for: complication,
                             download: 12_500_000,
                             upload:   3_200_000))
    }

    // MARK: - Factory methods

    private func makeEntry(for complication: CLKComplication) -> CLKComplicationTimelineEntry? {
        let session = WatchSessionManager.shared
        guard let template = makeTemplate(
            for: complication,
            download: session.downloadSpeed,
            upload:   session.uploadSpeed
        ) else { return nil }
        return CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
    }

    private func makeTemplate(
        for complication: CLKComplication,
        download: Double,
        upload: Double
    ) -> CLKComplicationTemplate? {

        let downText   = shortSpeed(download)
        let upText     = shortSpeed(upload)
        let bothText   = "↓\(downText) ↑\(upText)"

        switch complication.family {

        // ── Circular ──────────────────────────────────────────────────
        case .graphicCircular:
            let t = CLKComplicationTemplateGraphicCircularStackText()
            t.line1TextProvider = CLKSimpleTextProvider(
                text: downText, shortText: downText)
            t.line2TextProvider = CLKSimpleTextProvider(
                text: "↓", shortText: "↓")
            return t

        // ── Corner ────────────────────────────────────────────────────
        case .graphicCorner:
            let t = CLKComplicationTemplateGraphicCornerStackText()
            t.outerTextProvider = CLKSimpleTextProvider(
                text: downText, shortText: downText)
            t.innerTextProvider = CLKSimpleTextProvider(
                text: "↓ Net", shortText: "↓")
            return t

        // ── Bezel ──────────────────────────────────────────────────────
        case .graphicBezel:
            // graphicBezel requires a graphicCircular sub-template
            let inner = CLKComplicationTemplateGraphicCircularStackText()
            inner.line1TextProvider = CLKSimpleTextProvider(
                text: downText, shortText: downText)
            inner.line2TextProvider = CLKSimpleTextProvider(
                text: "↓", shortText: "↓")

            let t = CLKComplicationTemplateGraphicBezelCircularText()
            t.circularTemplate = inner
            t.textProvider = CLKSimpleTextProvider(
                text: bothText, shortText: downText)
            return t

        default:
            return nil
        }
    }

    // MARK: - Speed formatter (compact, for complication labels)

    /// Returns a compact speed string like "12.5M", "350K", "88B" (per second).
    private func shortSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec.isFinite, bytesPerSec >= 0 else { return "0B/s" }
        let units = ["B", "K", "M", "G"]
        var value = bytesPerSec
        var idx   = 0
        while value >= 1_024, idx < units.count - 1 {
            value /= 1_024
            idx   += 1
        }
        if idx == 0 {
            return String(format: "%.0f%@/s", value, units[idx])
        }
        return String(format: "%.1f%@/s", value, units[idx])
    }
}
