//
//  WatchNetworkView.swift
//  NetworkSpeedWatch
//
//  Main watch face screen.
//  • Digital Crown rotates between DOWNLOAD and UPLOAD views.
//  • Tap anywhere to open the companion iPhone app.
//  • Dark theme with blue (download) / orange (upload) accent colours.
//

import SwiftUI
import WatchKit

struct WatchNetworkView: View {

    @EnvironmentObject private var session: WatchSessionManager

    // 0.0 = download, 1.0 = upload (set by Digital Crown)
    @State private var crownValue: Double = 0.0
    @State private var showingDownload: Bool = true

    // MARK: - Derived values

    private var currentSpeed: Double {
        showingDownload ? session.downloadSpeed : session.uploadSpeed
    }

    private var accentColor: Color { showingDownload ? .blue : .orange }

    private var directionLabel: String { showingDownload ? "DOWNLOAD" : "UPLOAD" }

    private var directionIcon: String {
        showingDownload ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
    }

    private var interfaceIcon: String {
        switch session.activeInterface {
        case "wifi":     return "wifi"
        case "cellular": return "antenna.radiowaves.left.and.right"
        default:         return "xmark.circle"
        }
    }

    private var interfaceColor: Color {
        switch session.activeInterface {
        case "wifi":     return .blue
        case "cellular": return .orange
        default:         return .gray
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Direction pill ────────────────────────────────────
                HStack(spacing: 5) {
                    Image(systemName: directionIcon)
                        .font(.system(size: 11, weight: .semibold))
                    Text(directionLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundColor(accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(accentColor.opacity(0.18), in: Capsule())
                .padding(.top, 4)

                Spacer(minLength: 0)

                // ── Big speed readout ─────────────────────────────────
                let components = formatSpeed(currentSpeed)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(components.value)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.45)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.25), value: components.value)

                    Text(components.unit)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                        .padding(.bottom, 2)
                }

                // ── Interface badge ───────────────────────────────────
                HStack(spacing: 5) {
                    Image(systemName: interfaceIcon)
                        .font(.system(size: 11))
                        .foregroundColor(interfaceColor)
                    Text(session.activeInterface == "none" ? "Offline"
                         : session.activeInterface.capitalized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.top, 6)

                Spacer(minLength: 0)

                // ── Daily usage row ───────────────────────────────────
                HStack(spacing: 10) {
                    Label(formatBytes(session.todayWifiBytes),
                          systemImage: "wifi")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Label(formatBytes(session.todayCellularBytes),
                          systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 8)
        }
        // Digital Crown rotates between download (0) and upload (1)
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            through: 1,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                showingDownload = newValue < 0.5
            }
        }
        .onTapGesture {
            openPhoneApp()
        }
    }

    // MARK: - Actions

    /// Asks the iPhone companion app to come to the foreground.
    private func openPhoneApp() {
        session.requestOpenApp()
    }

    // MARK: - Formatting helpers

    private func formatSpeed(_ bytesPerSec: Double) -> (value: String, unit: String) {
        guard bytesPerSec.isFinite, bytesPerSec >= 0 else { return ("0", "B/s") }
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bytesPerSec
        var idx = 0
        while value >= 1_024, idx < units.count - 1 {
            value /= 1_024
            idx += 1
        }
        let formatted = idx == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return (formatted, units[idx])
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .binary
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    WatchNetworkView()
        .environmentObject(WatchSessionManager.shared)
}
