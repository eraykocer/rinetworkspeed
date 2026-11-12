//
//  SpeedShareCardView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import UIKit

// MARK: - Format

enum ShareCardFormat: String, CaseIterable {
    case square = "Square (1:1)"
    case story  = "Story (9:16)"

    var size: CGSize {
        switch self {
        case .square: return CGSize(width: 1080, height: 1080)
        case .story:  return CGSize(width: 1080, height: 1920)
        }
    }
}

// MARK: - Card View

struct SpeedShareCardView: View {
    let result: SpeedTestResult
    let format: ShareCardFormat
    let ssid: String?
    let isWifi: Bool

    // Same unit as the result screen (megabits per second).
    private var downloadMbps: Double { result.score.downloadMbps }
    private var uploadMbps:   Double { result.score.uploadMbps }
    private var isStory: Bool { format == .story }

    private var grade: String { result.score.grade }
    private var gradeColor: Color { result.score.gradeColor }

    var body: some View {
        ZStack {
            background
            content
        }
        .frame(width: format.size.width, height: format.size.height)
        // The shared image keeps the dark design regardless of the app theme.
        .environment(\.colorScheme, .dark)
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            AppTheme.background

            // Subtle grid
            Canvas { ctx, size in
                let spacing: CGFloat = isStory ? 80 : 54
                var path = Path()
                stride(from: CGFloat(0), through: size.width,  by: spacing).forEach { x in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                stride(from: CGFloat(0), through: size.height, by: spacing).forEach { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                ctx.stroke(path, with: .color(.white.opacity(0.04)), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Content

    private var content: some View {
        VStack(spacing: 0) {
            headerSection
            Spacer()
            gradeSection
            Spacer()
            speedSection
            Spacer()
            footerSection
        }
        .padding(.horizontal, 64)
        .padding(.top, isStory ? 140 : 90)
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(spacing: isStory ? 22 : 16) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: isStory ? 64 : 46, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: isStory ? 132 : 96, height: isStory ? 132 : 96)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: isStory ? 36 : 26, style: .continuous))
                .shadow(color: AppTheme.accent.opacity(0.45), radius: 30, x: 0, y: 12)

            Text(verbatim: "RiNetwork")
                .font(.system(size: isStory ? 56 : 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Speed Test Results")
                .font(.system(size: isStory ? 26 : 19, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(2)
        }
    }

    // MARK: Grade

    private var gradeSection: some View {
        VStack(spacing: isStory ? 18 : 12) {
            ZStack {
                Circle()
                    .fill(gradeColor.opacity(0.12))
                    .overlay(
                        Circle().stroke(gradeColor.opacity(0.7), lineWidth: 4)
                    )
                    .frame(width: isStory ? 190 : 150, height: isStory ? 190 : 150)

                Text(grade)
                    .font(.system(size: isStory ? 100 : 80, weight: .black, design: .rounded))
                    .foregroundStyle(gradeColor)
            }
            .shadow(color: gradeColor.opacity(0.45), radius: 32)

            Text("Network Quality Score")
                .font(.system(size: isStory ? 24 : 17, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(1.5)
        }
    }

    // MARK: Speed

    private var speedSection: some View {
        VStack(spacing: isStory ? 42 : 28) {
            // Download / Upload row
            HStack(spacing: 0) {
                speedCard(
                    icon: "arrow.down.circle.fill",
                    label: "Download",
                    value: downloadMbps.fixed(1),
                    unit: "Mbps",
                    color: AppTheme.download
                )

                Rectangle()
                    .fill(AppTheme.separator)
                    .frame(width: 1, height: isStory ? 110 : 84)

                speedCard(
                    icon: "arrow.up.circle.fill",
                    label: "Upload",
                    value: uploadMbps.fixed(1),
                    unit: "Mbps",
                    color: AppTheme.upload
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, isStory ? 32 : 22)
            .background(
                RoundedRectangle(cornerRadius: isStory ? 44 : 36, style: .continuous)
                    .fill(AppTheme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: isStory ? 44 : 36, style: .continuous)
                            .stroke(AppTheme.cardStroke, lineWidth: 2)
                    )
            )

            // Badges row
            HStack(spacing: isStory ? 28 : 20) {
                pingBadge
                if let ssid = ssid, !ssid.isEmpty {
                    networkBadge(ssid: ssid)
                }
            }
        }
    }

    private func speedCard(
        icon: String, label: String, value: String, unit: String, color: Color
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: isStory ? 30 : 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: isStory ? 68 : 54, height: isStory ? 68 : 54)
                .background(color, in: RoundedRectangle(cornerRadius: isStory ? 19 : 15, style: .continuous))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: isStory ? 64 : 50, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.system(size: isStory ? 22 : 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text(label)
                .font(.system(size: isStory ? 22 : 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(1.2)
        }
        .frame(maxWidth: .infinity)
    }

    private var pingBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: isStory ? 22 : 16, weight: .semibold))
                .foregroundStyle(AppTheme.ping)
            Text(result.ping.fixed(0) + " ms")
                .font(.system(size: isStory ? 28 : 21, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text("Ping")
                .font(.system(size: isStory ? 20 : 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(AppTheme.cardFill)
                .overlay(Capsule().stroke(AppTheme.cardStroke, lineWidth: 2))
        )
    }

    private func networkBadge(ssid: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isWifi ? "wifi" : "antenna.radiowaves.left.and.right")
                .font(.system(size: isStory ? 18 : 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
            Text(ssid)
                .font(.system(size: isStory ? 24 : 17, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(AppTheme.cardFill)
                .overlay(Capsule().stroke(AppTheme.cardStroke, lineWidth: 2))
        )
    }

    // MARK: Footer

    private var footerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: isStory ? 24 : 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                Text(result.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: isStory ? 20 : 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
            Text(verbatim: "RiNetwork")
                .font(.system(size: isStory ? 20 : 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.bottom, isStory ? 90 : 60)
    }
}

// MARK: - Generator

@MainActor
final class ShareCardGenerator {

    func generate(
        result: SpeedTestResult,
        format: ShareCardFormat,
        ssid: String? = nil,
        isWifi: Bool = true
    ) -> UIImage? {
        let view = SpeedShareCardView(
            result: result,
            format: format,
            ssid: ssid,
            isWifi: isWifi
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0  // card is already at pixel dimensions
        return renderer.uiImage
    }
}

// MARK: - Share Preview Sheet

struct SpeedSharePreviewSheet: View {
    let result: SpeedTestResult
    let ssid: String?
    let isWifi: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ShareCardFormat = .square
    @State private var cardEntryScale: CGFloat = 0.1
    @State private var isSharing: Bool = false

    private let generator = ShareCardGenerator()

    // Scaled-down preview dimensions (fits on screen)
    private let maxPreviewWidth: CGFloat = 280

    private var previewScale: CGFloat {
        maxPreviewWidth / selectedFormat.size.width
    }

    private var previewWidth: CGFloat  { maxPreviewWidth }
    private var previewHeight: CGFloat { selectedFormat.size.height * previewScale }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {

                        // Format picker
                        Picker("Format", selection: $selectedFormat) {
                            ForEach(ShareCardFormat.allCases, id: \.self) { fmt in
                                Text(fmt.rawValue).tag(fmt)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                        .onChange(of: selectedFormat) { _, _ in
                            animateCardEntry()
                        }

                        // Live card preview
                        cardPreview

                        // Share button
                        Button {
                            shareCard()
                        } label: {
                            HStack(spacing: 10) {
                                if isSharing {
                                    ProgressView().tint(.white).scaleEffect(0.9)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                Text(isSharing ? "Preparing..." : "Share")
                                    .fontWeight(.bold)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .shadow(color: AppTheme.accent.opacity(0.35), radius: 16, x: 0, y: 8)
                        .disabled(isSharing)
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Speed Share Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .onAppear { animateCardEntry() }
    }

    // MARK: Card preview

    private var cardPreview: some View {
        ZStack {
            // Blur background behind the card
            RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
                .fill(AppTheme.cardFill)
                .frame(width: previewWidth + 32, height: previewHeight + 32)
                .blur(radius: 8)

            SpeedShareCardView(
                result: result,
                format: selectedFormat,
                ssid: ssid,
                isWifi: isWifi
            )
            .frame(width: selectedFormat.size.width, height: selectedFormat.size.height)
            .scaleEffect(previewScale)
            .frame(width: previewWidth, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 24, x: 0, y: 10)
        }
        .scaleEffect(cardEntryScale)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: cardEntryScale)
    }

    // MARK: Actions

    private func animateCardEntry() {
        cardEntryScale = 0.1
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            cardEntryScale = 1.0
        }
    }

    private func shareCard() {
        isSharing = true
        Task {
            let image = generator.generate(
                result: result,
                format: selectedFormat,
                ssid: ssid,
                isWifi: isWifi
            )
            isSharing = false
            guard let image else { return }
            presentActivityViewController(items: [image])
        }
    }

    private func presentActivityViewController(items: [Any]) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(
                x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY,
                width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }
        rootVC.present(activityVC, animated: true) {
            self.dismiss()
        }
    }
}

#Preview {
    SpeedSharePreviewSheet(
        result: SpeedTestResult(date: .now, downloadSpeed: 52_000_000, uploadSpeed: 18_000_000, ping: 14),
        ssid: "Home WiFi",
        isWifi: true
    )
    .preferredColorScheme(.dark)
}
