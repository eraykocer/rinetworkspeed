//
//  WhoisView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI
import Combine

// MARK: - Whois API Response Models
// Using https://who-dat.as93.net/{domain}

private struct WhoisAPIResponse: Decodable {
    let domain: WhoisDomain?
    let registrar: WhoisRegistrar?
    let registrant: WhoisContact?
    let administrative: WhoisContact?
    let technical: WhoisContact?

    enum CodingKeys: String, CodingKey {
        case domain, registrar, registrant, administrative, technical
    }
}

private struct WhoisDomain: Decodable {
    let id: String?
    let domain: String?
    let punycode: String?
    let name: String?
    let extension_: String?
    let whois_server: String?
    let status: [String]?
    let name_servers: [String]?
    let created_date: String?
    let updated_date: String?
    let expiration_date: String?
    let estimated_domain_age: Int?

    enum CodingKeys: String, CodingKey {
        case id, domain, punycode, name
        case extension_ = "extension"
        case whois_server, status, name_servers
        case created_date, updated_date, expiration_date
        case estimated_domain_age
    }
}

private struct WhoisRegistrar: Decodable {
    let id: String?
    let name: String?
    let phone: String?
    let email: String?
    let referral_url: String?
}

private struct WhoisContact: Decodable {
    let id: String?
    let name: String?
    let organization: String?
    let street: String?
    let city: String?
    let province: String?
    let postal_code: String?
    let country: String?
    let phone: String?
    let email: String?
}

// MARK: - View Model

struct WhoisData {
    let domainName: String
    let registrar: String?
    let createdDate: String?
    let updatedDate: String?
    let expirationDate: String?
    let nameServers: [String]
    let status: [String]
    let registrantOrg: String?
    let registrantCountry: String?
    let domainAge: String?
}

@MainActor
final class WhoisViewModel: ObservableObject {
    @Published var domain: String = ""
    @Published var data: WhoisData?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func lookup() {
        let input = domain.trimmingCharacters(in: .whitespaces)
                          .replacingOccurrences(of: "https://", with: "")
                          .replacingOccurrences(of: "http://", with: "")
                          .components(separatedBy: "/").first ?? ""
        guard !input.isEmpty else { return }

        isLoading = true
        data = nil
        errorMessage = nil

        Task {
            do {
                data = try await fetchWhois(for: input)
            } catch {
                errorMessage = String(localized: "Lookup failed: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    private func fetchWhois(for domain: String) async throws -> WhoisData {
        guard let url = URL(string: "https://who-dat.as93.net/\(domain)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "Whois", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: String(localized: "HTTP \(http.statusCode) — domain may not be registered or whois data unavailable.")])
        }

        let decoded = try JSONDecoder().decode(WhoisAPIResponse.self, from: data)
        let dom = decoded.domain

        let ageString: String?
        if let age = dom?.estimated_domain_age {
            ageString = String(localized: "\(age) days (~\(age / 365) years)")
        } else {
            ageString = nil
        }

        return WhoisData(
            domainName:      dom?.domain ?? domain,
            registrar:       decoded.registrar?.name,
            createdDate:     dom?.created_date,
            updatedDate:     dom?.updated_date,
            expirationDate:  dom?.expiration_date,
            nameServers:     dom?.name_servers ?? [],
            status:          dom?.status ?? [],
            registrantOrg:   decoded.registrant?.organization ?? decoded.registrant?.name,
            registrantCountry: decoded.registrant?.country,
            domainAge:       ageString
        )
    }
}

// MARK: - View

struct WhoisView: View {
    @StateObject private var vm = WhoisViewModel()
    @FocusState private var fieldFocused: Bool

    private let accent     = Color(red: 0.99, green: 0.37, blue: 0.37)
    private let accentDeep = Color(red: 0.72, green: 0.12, blue: 0.12)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                heroCard

                if vm.isLoading {
                    ToolLoadingCard(message: "Querying Whois for \(vm.domain)…", tint: accent)
                } else if let err = vm.errorMessage {
                    ToolErrorCard(title: "Not Found", message: err, icon: "questionmark.bubble")
                } else if let data = vm.data {
                    resultsView(data)
                } else {
                    AppEmptyState(
                        icon: "doc.text.magnifyingglass",
                        title: "Enter a Domain",
                        message: "Type a domain name above to look up registration details."
                    )
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .appPageBackground()
        .navigationTitle("Whois")
        .toolReport(vm) { $0.reportText }
        .navigationBarTitleDisplayMode(.large)
        .onTapGesture { fieldFocused = false }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            ToolHeroHeader(
                icon: "doc.text.magnifyingglass",
                title: "Domain registration information",
                subtitle: "Look up the registrar, key dates and name servers of a domain."
            )

            AppInputField(icon: "globe", placeholder: "Domain (e.g. github.com)", text: $vm.domain, showsFavorites: true) {
                vm.lookup()
            }
            .focused($fieldFocused)
            .heroInset()

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
                    Text("Query")
                }
            }
            .buttonStyle(AppPrimaryButtonStyle(variant: .inverted, tint: accentDeep))
        }
        .appHeroCard(tint: accentDeep)
    }

    // MARK: - Results

    private func resultsView(_ data: WhoisData) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            domainHeader(data)

            infoSection(title: "Dates", entries: [
                ("Registered", data.createdDate ?? "—"),
                ("Updated",    data.updatedDate ?? "—"),
                ("Expires",    data.expirationDate ?? "—"),
                ("Domain Age", data.domainAge ?? "—")
            ])

            if let reg = data.registrar {
                infoSection(title: "Registrar", entries: [("Name", reg)])
            }

            let registrant = registrantEntries(data)
            if !registrant.isEmpty {
                infoSection(title: "Registrant", entries: registrant)
            }

            if !data.status.isEmpty {
                statusSection(data.status)
            }

            if !data.nameServers.isEmpty {
                nameServersSection(data.nameServers)
            }
        }
    }

    private func registrantEntries(_ data: WhoisData) -> [(LocalizedStringKey, String)] {
        var entries: [(LocalizedStringKey, String)] = []
        if let org = data.registrantOrg { entries.append(("Organization", org)) }
        if let country = data.registrantCountry { entries.append(("Country", country)) }
        return entries
    }

    private func domainHeader(_ data: WhoisData) -> some View {
        HStack(spacing: 14) {
            AppIconTile(systemName: "globe", tint: accent, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(data.domainName.uppercased())
                    .appFont(size: 18, weight: .bold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)
                    .textSelection(.enabled)
                if let reg = data.registrar {
                    Text(reg)
                        .appFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .appCard()
    }

    private func infoSection(title: LocalizedStringKey, entries: [(LocalizedStringKey, String)]) -> some View {
        AppSection(title) {
            ForEach(Array(entries.enumerated()), id: \.offset) { idx, entry in
                KeyValueRow(label: entry.0, value: entry.1)
                if idx < entries.count - 1 {
                    AppRowDivider(leadingInset: 16)
                }
            }
        }
    }

    private func statusSection(_ statuses: [String]) -> some View {
        AppSection("Status") {
            FlowLayout(spacing: 6) {
                ForEach(Array(statuses.enumerated()), id: \.offset) { _, status in
                    AppPill(text: "\(status.components(separatedBy: " ").first ?? status)",
                            tint: AppTheme.ink.opacity(0.75))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func nameServersSection(_ ns: [String]) -> some View {
        AppSection("Name Servers") {
            ForEach(Array(ns.enumerated()), id: \.offset) { idx, server in
                HStack(spacing: 14) {
                    AppIconTile(systemName: "server.rack", tint: accent, size: 32)
                    Text(server.lowercased())
                        .appFont(size: 14, weight: .medium, design: .monospaced)
                        .foregroundStyle(AppTheme.primaryText)
                        .textSelection(.enabled)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                if idx < ns.count - 1 {
                    AppRowDivider(leadingInset: 62)
                }
            }
        }
    }
}

// MARK: - Flow Layout

/// Wraps pills onto new lines when they run out of horizontal space.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            widest = max(widest, min(x + size.width, maxWidth))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y),
                          proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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

/// Label/value row used inside result sections.
private struct KeyValueRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .appFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 96, alignment: .leading)
            Text(verbatim: value)
                .appFont(size: 13, weight: .medium, design: .monospaced)
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
        WhoisView()
    }
    .preferredColorScheme(.dark)
}
