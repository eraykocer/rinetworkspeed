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
                errorMessage = "Lookup failed: \(error.localizedDescription)"
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
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) — domain may not be registered or whois data unavailable."])
        }

        let decoded = try JSONDecoder().decode(WhoisAPIResponse.self, from: data)
        let dom = decoded.domain

        let ageString: String?
        if let age = dom?.estimated_domain_age {
            ageString = "\(age) days (~\(age / 365) years)"
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

    private let bg     = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    private let accent = Color(red: 0.99, green: 0.37, blue: 0.37)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                inputCard
                if vm.isLoading { loadingView }
                else if let err = vm.errorMessage { errorView(err) }
                else if let data = vm.data { resultsView(data) }
                else { placeholderView }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(bg.ignoresSafeArea())
        .navigationTitle("Whois")
        .navigationBarTitleDisplayMode(.large)
        .onTapGesture { fieldFocused = false }
    }

    // MARK: - Input Card

    private var inputCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)

            TextField("Domain (e.g. github.com)", text: $vm.domain)
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .focused($fieldFocused)
                .onSubmit { vm.lookup() }

            Button {
                fieldFocused = false
                vm.lookup()
            } label: {
                Text("Query")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(
                            LinearGradient(colors: [accent, Color(red: 0.72, green: 0.12, blue: 0.12)],
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

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(accent)
            Text("Querying Whois for \(vm.domain)…")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(40)
    }

    private func errorView(_ msg: String) -> some View {
        ContentUnavailableView("Not Found", systemImage: "questionmark.bubble",
                               description: Text(msg))
        .foregroundStyle(.white)
    }

    private var placeholderView: some View {
        ContentUnavailableView(
            "Enter a Domain",
            systemImage: "doc.text.magnifyingglass",
            description: Text("Type a domain name above to look up registration details.")
        )
        .foregroundStyle(.white)
        .padding(.top, 30)
    }

    // MARK: - Results

    private func resultsView(_ data: WhoisData) -> some View {
        VStack(spacing: 14) {
            // Domain header
            domainHeader(data)

            // Dates card
            infoCard(title: "Dates", entries: [
                ("Registered", data.createdDate ?? "—"),
                ("Updated",    data.updatedDate ?? "—"),
                ("Expires",    data.expirationDate ?? "—"),
                ("Domain Age", data.domainAge ?? "—")
            ])

            // Registrar card
            if let reg = data.registrar {
                infoCard(title: "Registrar", entries: [("Name", reg)])
            }

            // Registrant card
            let registrantEntries: [(String, String)] = [
                data.registrantOrg.map { ("Organization", $0) },
                data.registrantCountry.map { ("Country", $0) }
            ].compactMap { $0 }
            if !registrantEntries.isEmpty {
                infoCard(title: "Registrant", entries: registrantEntries)
            }

            // Status card
            if !data.status.isEmpty {
                statusCard(data.status)
            }

            // Name servers card
            if !data.nameServers.isEmpty {
                nameServersCard(data.nameServers)
            }
        }
    }

    private func domainHeader(_ data: WhoisData) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [accent.opacity(0.25), Color(red: 0.72, green: 0.12, blue: 0.12).opacity(0.15)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                Image(systemName: "globe")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(data.domainName.uppercased())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let reg = data.registrar {
                    Text(reg)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(accent.opacity(0.20), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func infoCard(title: String, entries: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            sectionHeader(title)
            Divider().background(Color.white.opacity(0.08))
            ForEach(Array(entries.enumerated()), id: \.offset) { idx, entry in
                infoRow(label: entry.0, value: entry.1)
                if idx < entries.count - 1 {
                    Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                }
            }
        }
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusCard(_ statuses: [String]) -> some View {
        VStack(spacing: 0) {
            sectionHeader("Status")
            Divider().background(Color.white.opacity(0.08))
            FlowLayout(items: statuses) { status in
                Text(status.components(separatedBy: " ").first ?? status)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.70))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(14)
        }
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func nameServersCard(_ ns: [String]) -> some View {
        VStack(spacing: 0) {
            sectionHeader("Name Servers")
            Divider().background(Color.white.opacity(0.08))
            ForEach(Array(ns.enumerated()), id: \.offset) { idx, server in
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 13))
                        .foregroundStyle(accent.opacity(0.60))
                        .frame(width: 20)
                    Text(server.lowercased())
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.80))
                        .textSelection(.enabled)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                if idx < ns.count - 1 {
                    Divider().background(Color.white.opacity(0.06)).padding(.leading, 48)
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
                .foregroundStyle(.white.opacity(0.50))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Simple Flow Layout

private struct FlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    private var rows: [[Item]] {
        var result: [[Item]] = [[]]
        for (i, item) in items.enumerated() {
            if i % 3 == 0 && i != 0 { result.append([]) }
            result[result.count - 1].append(item)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { item in
                        content(item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        WhoisView()
    }
}
