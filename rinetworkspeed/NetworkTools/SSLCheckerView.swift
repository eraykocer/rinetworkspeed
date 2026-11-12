//
//  SSLCheckerView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Combine
import Security
import CryptoKit

// MARK: - Models

struct CertificateInfo {
    let subjectSummary: String
    let issuerName: String
    let notBefore: Date?
    let notAfter: Date?
    let sha256Fingerprint: String
    let chain: [String]

    var daysRemaining: Int? {
        guard let expiry = notAfter else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    }

    var isExpired: Bool {
        guard let d = daysRemaining else { return false }
        return d < 0
    }

    var statusColor: Color {
        guard let d = daysRemaining else { return .gray }
        if d < 0  { return .red }
        if d < 30 { return .yellow }
        return .green
    }

    var statusLabel: String {
        guard let d = daysRemaining else { return "Unknown" }
        if d < 0  { return "Expired \(abs(d)) days ago" }
        if d == 0 { return "Expires today" }
        if d < 30 { return "\(d) days remaining — expiring soon" }
        return "\(d) days remaining"
    }
}

// MARK: - SSL Session Delegate

private final class SSLDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    var capturedInfo: CertificateInfo?

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        capturedInfo = Self.extractInfo(from: serverTrust)
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    private static func extractInfo(from trust: SecTrust) -> CertificateInfo? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }

        let subject = SecCertificateCopySubjectSummary(leaf) as String? ?? "Unknown"
        let notBefore = SecCertificateCopyNotValidBeforeDate(leaf) as Date?
        let notAfter = SecCertificateCopyNotValidAfterDate(leaf) as Date?

        let issuerCertificate = chain.dropFirst().first
        let issuer = issuerCertificate.flatMap(commonName(for:))
            ?? issuerCertificate.flatMap { SecCertificateCopySubjectSummary($0) as String? }
            ?? "Unknown"

        // SHA-256 fingerprint
        let derData = SecCertificateCopyData(leaf) as Data
        let hash = SHA256.hash(data: derData)
        let fingerprint = hash.map { String(format: "%02X", $0) }.joined(separator: ":")

        let chainNames = chain.compactMap { SecCertificateCopySubjectSummary($0) as String? }

        return CertificateInfo(
            subjectSummary: subject,
            issuerName: issuer,
            notBefore: notBefore,
            notAfter: notAfter,
            sha256Fingerprint: fingerprint,
            chain: chainNames
        )
    }

    private static func commonName(for certificate: SecCertificate) -> String? {
        var commonName: CFString?
        let status = SecCertificateCopyCommonName(certificate, &commonName)
        guard status == errSecSuccess else { return nil }
        return commonName as String?
    }
}

// MARK: - ViewModel

@MainActor
final class SSLCheckerViewModel: ObservableObject {
    @Published var hostname: String = ""
    @Published var certInfo: CertificateInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    func check() {
        let stripped = hostname.trimmingCharacters(in: .whitespaces)
                               .replacingOccurrences(of: "https://", with: "")
                               .replacingOccurrences(of: "http://", with: "")
        let host = stripped.components(separatedBy: "/").first ?? stripped
        guard !host.isEmpty else { return }
        isLoading = true
        certInfo = nil
        errorMessage = nil

        Task {
            do {
                certInfo = try await fetchCert(host: host)
                if certInfo == nil {
                    errorMessage = "No certificate information could be extracted."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func fetchCert(host: String) async throws -> CertificateInfo? {
        guard let url = URL(string: "https://\(host)") else {
            throw URLError(.badURL)
        }
        let delegate = SSLDelegate()
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        _ = try? await session.data(for: req)
        return delegate.capturedInfo
    }

    func formatted(_ date: Date?) -> String {
        guard let d = date else { return "—" }
        return dateFormatter.string(from: d)
    }
}

// MARK: - View

struct SSLCheckerView: View {
    @StateObject private var vm = SSLCheckerViewModel()
    @FocusState private var fieldFocused: Bool

    private let accent     = Color(red: 0.20, green: 0.75, blue: 0.99)
    private let accentDeep = Color(red: 0.08, green: 0.40, blue: 0.72)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                heroCard

                if vm.isLoading {
                    ToolLoadingCard(message: "Connecting to \(vm.hostname)…", tint: accent)
                } else if let err = vm.errorMessage {
                    ToolErrorCard(title: "Check Failed", message: err, icon: "lock.slash")
                } else if let info = vm.certInfo {
                    statusCard(info)
                    detailsSection(info)
                    chainSection(info)
                } else {
                    AppEmptyState(
                        icon: "lock.shield",
                        title: "Enter a Domain",
                        message: "Type a domain name above and tap Check to inspect its SSL certificate."
                    )
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .appPageBackground()
        .navigationTitle("SSL Checker")
        .navigationBarTitleDisplayMode(.large)
        .onTapGesture { fieldFocused = false }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            ToolHeroHeader(
                icon: "lock.shield.fill",
                title: "Certificate validity & details",
                subtitle: "Inspect the TLS certificate, issuer and expiry date of any HTTPS site."
            )

            AppInputField(icon: "globe", placeholder: "Domain (e.g. apple.com)", text: $vm.hostname) {
                vm.check()
            }
            .focused($fieldFocused)
            .heroInset()

            Button {
                fieldFocused = false
                vm.check()
            } label: {
                HStack(spacing: 8) {
                    if vm.isLoading {
                        ProgressView().tint(accentDeep)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                    }
                    Text("Check")
                }
            }
            .buttonStyle(AppPrimaryButtonStyle(variant: .inverted, colors: [accent, accentDeep]))
        }
        .appHeroCard(colors: [accent, accentDeep])
    }

    // MARK: - Status Card

    private func statusPill(_ info: CertificateInfo) -> LocalizedStringKey {
        guard let days = info.daysRemaining else { return "Unknown" }
        if days < 0 { return "Expired" }
        if days < 30 { return "Expiring Soon" }
        return "Valid"
    }

    private func statusCard(_ info: CertificateInfo) -> some View {
        HStack(spacing: 14) {
            AppIconTile(systemName: info.isExpired ? "xmark.shield.fill" : "checkmark.shield.fill",
                        tint: info.statusColor, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.subjectSummary)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                Text(info.statusLabel)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(info.statusColor)
            }

            Spacer(minLength: 8)

            AppPill(text: statusPill(info), tint: info.statusColor)
        }
        .appCard()
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(info.statusColor.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Details Section

    private func detailsSection(_ info: CertificateInfo) -> some View {
        AppSection("Certificate Details") {
            KeyValueRow(label: "Subject", value: info.subjectSummary)
            AppRowDivider(leadingInset: 16)
            KeyValueRow(label: "Issuer", value: info.issuerName)
            AppRowDivider(leadingInset: 16)
            KeyValueRow(label: "Valid From", value: vm.formatted(info.notBefore))
            AppRowDivider(leadingInset: 16)
            KeyValueRow(label: "Expires", value: vm.formatted(info.notAfter))
            AppRowDivider(leadingInset: 16)

            VStack(alignment: .leading, spacing: 6) {
                Text("SHA-256 Fingerprint")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(info.sha256Fingerprint)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.primaryText.opacity(0.85))
                    .textSelection(.enabled)
                    .lineLimit(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }

    // MARK: - Chain Section

    private func chainSection(_ info: CertificateInfo) -> some View {
        AppSection("Certificate Chain") {
            ForEach(Array(info.chain.enumerated()), id: \.offset) { index, name in
                HStack(spacing: 14) {
                    Text(verbatim: "\(index + 1)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(index == 0 ? .white : AppTheme.secondaryText)
                        .frame(width: 40, height: 40)
                        .background(chainTileFill(isLeaf: index == 0),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                    Text(name)
                        .font(.system(size: 15, weight: index == 0 ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(index == 0 ? AppTheme.primaryText : AppTheme.secondaryText)
                        .lineLimit(1)
                        .textSelection(.enabled)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if index < info.chain.count - 1 {
                    AppRowDivider()
                }
            }
        }
    }

    private func chainTileFill(isLeaf: Bool) -> AnyShapeStyle {
        isLeaf
            ? AnyShapeStyle(LinearGradient(colors: [accent, accent.opacity(0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(Color.white.opacity(0.06))
    }
}

// MARK: - Tool Page Components

/// Icon tile + short description shown at the top of the tool's hero card.
private struct ToolHeroHeader: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private extension View {
    /// Darkened inset so inputs and controls stay legible on the hero gradient.
    func heroInset() -> some View {
        background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }
}

/// Card explaining why the last run failed.
private struct ToolErrorCard: View {
    let title: LocalizedStringKey
    let message: String
    var icon = "exclamationmark.triangle.fill"

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AppIconTile(systemName: icon, tint: AppTheme.danger)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Text(verbatim: message)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .appCard()
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.danger.opacity(0.35), lineWidth: 1)
        )
    }
}

/// Inline progress card shown while a request is in flight.
private struct ToolLoadingCard: View {
    let message: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(tint)
                .frame(width: 40, height: 40)
            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .appCard(padding: nil)
    }
}

/// Label/value row used inside result sections.
private struct KeyValueRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 96, alignment: .leading)
            Text(verbatim: value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.primaryText)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

#Preview {
    NavigationStack {
        SSLCheckerView()
    }
    .preferredColorScheme(.dark)
}
