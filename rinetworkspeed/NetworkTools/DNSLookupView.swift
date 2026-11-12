//
//  DNSLookupView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Combine

// MARK: - Models

struct DNSRecord: Identifiable {
    let id = UUID()
    let type: String
    let value: String
    let ttl: Int?
}

enum DNSRecordType: String, CaseIterable, Identifiable {
    case a     = "A"
    case aaaa  = "AAAA"
    case mx    = "MX"
    case txt   = "TXT"
    case cname = "CNAME"
    case ns    = "NS"

    var id: String { rawValue }

    var typeNumber: Int {
        switch self {
        case .a:     return 1
        case .ns:    return 2
        case .cname: return 5
        case .mx:    return 15
        case .txt:   return 16
        case .aaaa:  return 28
        }
    }

    var color: Color {
        switch self {
        case .a:     return Color(red: 0.24, green: 0.45, blue: 0.99)
        case .aaaa:  return Color(red: 0.55, green: 0.28, blue: 0.96)
        case .mx:    return Color(red: 0.98, green: 0.62, blue: 0.16)
        case .txt:   return Color(red: 0.13, green: 0.72, blue: 0.52)
        case .cname: return Color(red: 0.84, green: 0.28, blue: 0.74)
        case .ns:    return Color(red: 0.20, green: 0.75, blue: 0.99)
        }
    }
}

enum DNSServerOption: String, CaseIterable, Identifiable {
    case cloudflare = "Cloudflare"
    case google     = "Google"
    case system     = "System"

    var id: String { rawValue }

    var baseURL: String {
        switch self {
        case .cloudflare: return "https://cloudflare-dns.com/dns-query"
        case .google:     return "https://dns.google/resolve"
        case .system:     return "https://cloudflare-dns.com/dns-query"
        }
    }

    var icon: String {
        switch self {
        case .cloudflare: return "bolt.fill"
        case .google:     return "globe"
        case .system:     return "applelogo"
        }
    }
}

// MARK: - DoH Response

private struct DoHResponse: Decodable {
    let Status: Int
    let Answer: [DoHAnswerRecord]?
    let Authority: [DoHAnswerRecord]?
}

private struct DoHAnswerRecord: Decodable {
    let name: String
    let type: Int
    let TTL: Int
    let data: String
}

// MARK: - ViewModel

@MainActor
final class DNSLookupViewModel: ObservableObject {
    @Published var domain: String = ""
    @Published var records: [DNSRecord] = []
    @Published var selectedType: DNSRecordType = .a
    @Published var selectedServer: DNSServerOption = .cloudflare
    @Published var isLoading = false
    @Published var queryTime: Double?
    @Published var errorMessage: String?

    func lookup() {
        let domain = domain.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty else { return }
        isLoading = true
        records = []
        queryTime = nil
        errorMessage = nil

        Task {
            let start = Date()
            do {
                let fetched = try await fetchRecords(domain: domain,
                                                     type: selectedType,
                                                     server: selectedServer)
                queryTime = Date().timeIntervalSince(start) * 1000
                records = fetched
                if fetched.isEmpty {
                    errorMessage = "No \(selectedType.rawValue) records found for \(domain)"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Fetch

    private func fetchRecords(domain: String,
                               type: DNSRecordType,
                               server: DNSServerOption) async throws -> [DNSRecord] {
        var comps = URLComponents(string: server.baseURL)!
        comps.queryItems = [
            URLQueryItem(name: "name", value: domain),
            URLQueryItem(name: "type", value: type.rawValue)
        ]
        guard let url = comps.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: req)
        let response = try JSONDecoder().decode(DoHResponse.self, from: data)

        guard response.Status == 0 else {
            throw NSError(domain: "DNS", code: response.Status,
                          userInfo: [NSLocalizedDescriptionKey: dnsStatusMessage(response.Status)])
        }

        let answers = response.Answer ?? response.Authority ?? []
        return answers
            .filter { $0.type == type.typeNumber }
            .map { DNSRecord(type: typeString($0.type), value: $0.data, ttl: $0.TTL) }
    }

    private func typeString(_ number: Int) -> String {
        switch number {
        case 1:  return "A"
        case 2:  return "NS"
        case 5:  return "CNAME"
        case 15: return "MX"
        case 16: return "TXT"
        case 28: return "AAAA"
        default: return "TYPE\(number)"
        }
    }

    private func dnsStatusMessage(_ code: Int) -> String {
        switch code {
        case 1: return String(localized: "Format Error")
        case 2: return String(localized: "Server Failure")
        case 3: return String(localized: "Domain Not Found (NXDOMAIN)")
        case 4: return String(localized: "Not Implemented")
        case 5: return String(localized: "Query Refused")
        default: return String(localized: "DNS Error \(code)")
        }
    }
}

// MARK: - View

struct DNSLookupView: View {
    @StateObject private var vm = DNSLookupViewModel()
    @FocusState private var fieldFocused: Bool

    private let accent = Color(red: 0.98, green: 0.62, blue: 0.16)
    private let accentDeep = Color(red: 0.78, green: 0.39, blue: 0.05)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                heroCard

                if vm.isLoading {
                    ToolLoadingCard(message: "Querying \(vm.selectedServer.rawValue)…", tint: accent)
                } else if let err = vm.errorMessage {
                    ToolErrorCard(title: "No Results", message: err, icon: "globe.slash")
                } else if !vm.records.isEmpty {
                    resultsSection
                } else {
                    AppEmptyState(
                        icon: "globe.americas.fill",
                        title: "Enter a Domain",
                        message: "Choose a record type and tap Lookup to query its DNS records."
                    )
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .appPageBackground()
        .navigationTitle("DNS Lookup")
        .navigationBarTitleDisplayMode(.large)
        .onTapGesture { fieldFocused = false }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            ToolHeroHeader(
                icon: "globe.americas.fill",
                title: "Query DNS records for any domain",
                subtitle: "Resolve A, AAAA, MX, TXT, CNAME and NS records over DNS-over-HTTPS."
            )

            AppInputField(icon: "globe", placeholder: "Domain (e.g. apple.com)", text: $vm.domain) {
                vm.lookup()
            }
            .focused($fieldFocused)
            .heroInset()

            // Record type picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DNSRecordType.allCases) { type in
                        Button {
                            vm.selectedType = type
                        } label: {
                            HeroChip(title: type.rawValue, isSelected: vm.selectedType == type,
                                     selectedTint: type.color, monospaced: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            // DNS Server & Lookup
            HStack(spacing: 10) {
                Menu {
                    ForEach(DNSServerOption.allCases) { server in
                        Button {
                            vm.selectedServer = server
                        } label: {
                            Label(server.rawValue, systemImage: server.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: vm.selectedServer.icon)
                            .appFont(size: 13, weight: .semibold)
                        Text(verbatim: vm.selectedServer.rawValue)
                            .appFont(size: 14, weight: .semibold, design: .rounded)
                        Image(systemName: "chevron.down")
                            .appFont(size: 11, weight: .semibold)
                    }
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(.black.opacity(0.22)))
                }

                Button {
                    fieldFocused = false
                    vm.lookup()
                } label: {
                    HStack(spacing: 8) {
                        if vm.isLoading {
                            ProgressView().tint(accentDeep)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text("Lookup")
                    }
                }
                .buttonStyle(AppPrimaryButtonStyle(variant: .inverted, tint: accentDeep))
            }
        }
        .appHeroCard(tint: accentDeep)
    }

    // MARK: - Results

    private var queryTimeFooter: LocalizedStringKey? {
        guard let ms = vm.queryTime else { return nil }
        return "Query time: \(ms.fixed(1) + " ms")"
    }

    private var resultsSection: some View {
        AppSection("\(vm.records.count) records", footer: queryTimeFooter) {
            ForEach(vm.records) { record in
                DNSRecordRow(record: record, color: vm.selectedType.color)
                if record.id != vm.records.last?.id {
                    AppRowDivider(leadingInset: 16)
                }
            }
        }
    }
}

// MARK: - DNS Record Row

private struct DNSRecordRow: View {
    let record: DNSRecord
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AppPill(text: "\(record.type)", tint: color)

                if let ttl = record.ttl {
                    Text("TTL \(ttl)s")
                        .appFont(size: 11, weight: .medium, design: .monospaced)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }

            Text(verbatim: record.value)
                .appFont(size: 14, weight: .medium, design: .monospaced)
                .foregroundStyle(AppTheme.primaryText)
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
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
                .appFont(size: 24, weight: .semibold)
                .foregroundStyle(AppTheme.ink)
                .frame(width: 52, height: 52)
                .background(AppTheme.ink.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appFont(size: 19, weight: .bold, design: .rounded)
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .appFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
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
                    .appFont(size: 16, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)
                Text(verbatim: message)
                    .appFont(size: 13, weight: .regular, design: .rounded)
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
                .appFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .appCard(padding: nil)
    }
}

/// Selectable capsule used for options inside the hero card.
private struct HeroChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let selectedTint: Color
    var monospaced = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .appFont(size: 11, weight: .semibold)
            }
            Text(verbatim: title)
                .appFont(size: 13, weight: .semibold, design: monospaced ? .monospaced : .rounded)
        }
        .foregroundStyle(isSelected ? selectedTint : AppTheme.ink.opacity(0.85))
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(Capsule().fill(isSelected ? AppTheme.ink : Color.black.opacity(0.22)))
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

#Preview {
    NavigationStack {
        DNSLookupView()
    }
    .preferredColorScheme(.dark)
}
