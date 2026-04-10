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

    private let bg     = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    private let accent = Color(red: 0.20, green: 0.75, blue: 0.99)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                inputCard

                if vm.isLoading {
                    loadingView
                } else if let err = vm.errorMessage {
                    ContentUnavailableView("Check Failed", systemImage: "lock.slash",
                                          description: Text(err))
                    .foregroundStyle(.white)
                } else if let info = vm.certInfo {
                    validityCard(info)
                    detailsCard(info)
                    chainCard(info)
                } else {
                    placeholderView
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(bg.ignoresSafeArea())
        .navigationTitle("SSL Checker")
        .navigationBarTitleDisplayMode(.large)
        .onTapGesture { fieldFocused = false }
    }

    // MARK: - Input Card

    private var inputCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)

            TextField("Domain (e.g. apple.com)", text: $vm.hostname)
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .focused($fieldFocused)
                .onSubmit { vm.check() }

            Button {
                fieldFocused = false
                vm.check()
            } label: {
                Text("Check")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(
                            LinearGradient(colors: [accent, Color(red: 0.08, green: 0.40, blue: 0.72)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                    )
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(accent)
            Text("Connecting to \(vm.hostname)…")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(40)
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        ContentUnavailableView(
            "Enter a Domain",
            systemImage: "lock.shield",
            description: Text("Type a domain name above and tap Check to inspect its SSL certificate.")
        )
        .foregroundStyle(.white)
        .padding(.top, 30)
    }

    // MARK: - Validity Card

    private func validityCard(_ info: CertificateInfo) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(info.statusColor.opacity(0.15))
                    .frame(width: 54, height: 54)
                Image(systemName: info.isExpired ? "xmark.shield.fill" : "checkmark.shield.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(info.statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(info.subjectSummary)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(info.statusLabel)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(info.statusColor)
            }
            Spacer()
        }
        .padding(18)
        .background(info.statusColor.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(info.statusColor.opacity(0.30), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Details Card

    private func detailsCard(_ info: CertificateInfo) -> some View {
        VStack(spacing: 0) {
            sectionHeader("Certificate Details")
            Divider().background(Color.white.opacity(0.08))

            infoRow("Subject",    value: info.subjectSummary)
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
            infoRow("Issuer",     value: info.issuerName)
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
            infoRow("Valid From", value: vm.formatted(info.notBefore))
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
            infoRow("Expires",    value: vm.formatted(info.notAfter))
            Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)

            VStack(alignment: .leading, spacing: 6) {
                Text("SHA-256 Fingerprint")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                Text(info.sha256Fingerprint)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.70))
                    .textSelection(.enabled)
                    .lineLimit(4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Chain Card

    private func chainCard(_ info: CertificateInfo) -> some View {
        VStack(spacing: 0) {
            sectionHeader("Certificate Chain")
            Divider().background(Color.white.opacity(0.08))
            ForEach(Array(info.chain.enumerated()), id: \.offset) { index, name in
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accent.opacity(index == 0 ? 0.20 : 0.08))
                            .frame(width: 32, height: 32)
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent.opacity(index == 0 ? 1.0 : 0.50))
                    }
                    Text(name)
                        .font(.system(size: 13, weight: index == 0 ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(index == 0 ? .white : .white.opacity(0.55))
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                if index < info.chain.count - 1 {
                    Divider().background(Color.white.opacity(0.06)).padding(.leading, 62)
                }
            }
        }
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        SSLCheckerView()
    }
}
