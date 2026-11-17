//
//  WiFiSignalView.swift
//  rinetworkspeed
//
//  The Wi-Fi signal card in the Wi-Fi details and the one-time setup of the
//  Shortcuts bridge (see WiFiSignal.swift).
//

import SwiftUI

// MARK: - Signal card

struct WiFiSignalGroup: View {
    @ObservedObject private var store = WiFiSignalStore.shared
    @State private var showingSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Signal")
                    .appFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .textCase(.uppercase)
                    .padding(.leading, 4)
                Spacer()
                if store.latest != nil {
                    Button {
                        showingSetup = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityLabel(Text("How signal reading works"))
                }
            }

            VStack(spacing: 0) {
                if let reading = store.latest {
                    readingRows(reading)
                    AppRowDivider(leadingInset: 16)
                    readButton
                } else {
                    introduction
                }
            }
            .appCard(padding: nil)
        }
        .sheet(isPresented: $showingSetup) {
            WiFiSignalSetupView()
        }
    }

    @ViewBuilder
    private func readingRows(_ reading: WiFiSignalReading) -> some View {
        if let rssi = reading.rssi {
            row(title: "Signal strength", value: "\(rssi) dBm", quality: SignalQuality(rssi: rssi))
            AppRowDivider(leadingInset: 16)
        }
        if let snr = reading.snr, let noise = reading.noise {
            row(title: "Noise", value: "\(noise) dBm")
            AppRowDivider(leadingInset: 16)
            row(title: "Signal-to-noise", value: "\(snr) dB", quality: SignalQuality(snr: snr))
            AppRowDivider(leadingInset: 16)
        }
        if let channel = reading.channel {
            row(title: "Channel", value: reading.band.map { "\(channel) · \($0.label)" } ?? "\(channel)")
            AppRowDivider(leadingInset: 16)
        }
        if let standard = reading.standard {
            row(title: "Wi-Fi standard", value: standard)
            AppRowDivider(leadingInset: 16)
        }
        if let tx = reading.txRate {
            let rx = reading.rxRate.map { " / \($0.fixed(0))" } ?? ""
            row(title: "Link rate", value: "\(tx.fixed(0))\(rx) Mbps")
            AppRowDivider(leadingInset: 16)
        }
        if let bssid = reading.bssid {
            row(title: "Access point", value: bssid)
            AppRowDivider(leadingInset: 16)
        }
        if store.accessPointChanged {
            Label("Connected to a different access point than at the previous reading.", systemImage: "arrow.triangle.swap")
                .appFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            AppRowDivider(leadingInset: 16)
        }
        Text("Read \(reading.date.formatted(.relative(presentation: .named)))")
            .appFont(size: 12, weight: .regular, design: .rounded)
            .foregroundStyle(AppTheme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iOS doesn't give apps the Wi-Fi signal strength. A small shortcut can read it for RiNetwork: signal, noise, channel and link rate.")
                .appFont(size: 14, weight: .regular, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set Up Signal Reading") { showingSetup = true }
                .buttonStyle(AppSecondaryButtonStyle())
        }
        .padding(16)
    }

    private var readButton: some View {
        Button {
            store.requestReading()
        } label: {
            HStack(spacing: 8) {
                if store.isWaiting {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "wifi")
                }
                Text(store.isWaiting ? "Waiting for the shortcut…" : "Read Signal Again")
            }
            .appFont(size: 14, weight: .semibold, design: .rounded)
            .foregroundStyle(AppTheme.download)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func row(title: LocalizedStringKey, value: String, quality: SignalQuality? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .appFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 8)
            if let quality {
                Text(quality.title)
                    .appFont(size: 12, weight: .bold, design: .rounded)
                    .foregroundStyle(quality.color)
            }
            Text(verbatim: value)
                .appFont(size: 14, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(AppTheme.ink)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private extension SignalQuality {
    var title: LocalizedStringKey {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .weak: return "Weak"
        }
    }

    var color: Color {
        switch self {
        case .excellent, .good: return AppTheme.ping
        case .fair: return AppTheme.warning
        case .weak: return AppTheme.danger
        }
    }
}

// MARK: - Setup

struct WiFiSignalSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var store = WiFiSignalStore.shared
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    Text("RiNetwork runs a shortcut that reads the Wi-Fi details and sends them back to the app. You set it up once; the values stay on this iPhone.")
                        .appFont(size: 15, weight: .regular, design: .rounded)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let shareURL = WiFiSignalStore.shortcutShareURL {
                        Button {
                            openURL(shareURL)
                        } label: {
                            Label("Add the Ready-Made Shortcut", systemImage: "plus.square.on.square")
                        }
                        .buttonStyle(AppSecondaryButtonStyle())
                        Text("Or build it yourself:")
                            .appFont(size: 13, weight: .semibold, design: .rounded)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    AppSection("Build the Shortcut") {
                        step(1, "Open the Shortcuts app and create a new shortcut.")
                        AppRowDivider(leadingInset: 16)
                        step(2, "Name it exactly “\(WiFiSignalStore.shortcutName)”.")
                        AppRowDivider(leadingInset: 16)
                        step(3, "Add the action “Get Network Details” seven times. Set each to Wi-Fi and pick one detail per action: RSSI, Noise, Channel Number, Wi-Fi Standard, TX Rate, RX Rate and BSSID.")
                        AppRowDivider(leadingInset: 16)
                        step(4, "Add “Open URLs” at the end and paste the address below. Replace each [name] with the matching action's result.")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: WiFiSignalStore.callbackTemplate)
                            .appFont(size: 12, weight: .regular, design: .monospaced)
                            .foregroundStyle(AppTheme.ink)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            UIPasteboard.general.string = WiFiSignalStore.callbackTemplate
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy Address", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(AppSecondaryButtonStyle())
                    }
                    .appCard()

                    Button {
                        store.requestReading()
                        dismiss()
                    } label: {
                        Label("Read Signal", systemImage: "wifi")
                    }
                    .buttonStyle(AppPrimaryButtonStyle())

                    Text("Each reading briefly opens the Shortcuts app and comes straight back. Readings are taken when you ask, not continuously.")
                        .appFont(size: 12, weight: .regular, design: .rounded)
                        .foregroundStyle(AppTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AppTheme.pagePadding)
            }
            .appPageBackground()
            .navigationTitle("Wi-Fi Signal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .appFont(size: 14, weight: .bold, design: .rounded)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(AppTheme.download, in: Circle())
            Text(text)
                .appFont(size: 14, weight: .regular, design: .rounded)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
