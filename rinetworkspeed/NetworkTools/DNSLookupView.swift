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
        case 1: return "Format Error"
        case 2: return "Server Failure"
        case 3: return "Domain Not Found (NXDOMAIN)"
        case 4: return "Not Implemented"
        case 5: return "Query Refused"
        default: return "DNS Error \(code)"
        }
    }
}

// MARK: - View

struct DNSLookupView: View {
    @StateObject private var vm = DNSLookupViewModel()
    @FocusState private var fieldFocused: Bool

    private let bg = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    private let accent = Color(red: 0.98, green: 0.62, blue: 0.16)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                queryCard
                if vm.isLoading { loadingView }
                else if let err = vm.errorMessage { errorView(err) }
                else if !vm.records.isEmpty { resultsList }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(bg.ignoresSafeArea())
        .navigationTitle("DNS Lookup")
        .navigationBarTitleDisplayMode(.large)
        .onTapGesture { fieldFocused = false }
    }

    // MARK: - Query Card

    private var queryCard: some View {
        VStack(spacing: 14) {
            // Domain input
            HStack(spacing: 12) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)

                TextField("Domain (e.g. apple.com)", text: $vm.domain)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .focused($fieldFocused)
                    .onSubmit { vm.lookup() }

                if !vm.domain.isEmpty {
                    Button { vm.domain = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Record type picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DNSRecordType.allCases) { type in
                        Button {
                            vm.selectedType = type
                        } label: {
                            Text(type.rawValue)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(vm.selectedType == type ? .white : .white.opacity(0.45))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(vm.selectedType == type
                                              ? type.color.opacity(0.25)
                                              : Color.white.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(vm.selectedType == type ? type.color.opacity(0.6) : Color.clear,
                                                lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            // DNS Server & Lookup
            HStack(spacing: 12) {
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
                            .font(.system(size: 13))
                        Text(vm.selectedServer.rawValue)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button {
                    fieldFocused = false
                    vm.lookup()
                } label: {
                    Text("Lookup")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [accent, Color(red: 0.78, green: 0.39, blue: 0.05)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            // Query time
            if let ms = vm.queryTime {
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                    Text("Query time: \(String(format: "%.1f ms", ms))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.40))
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Results

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(accent)
            Text("Querying \(vm.selectedServer.rawValue)…")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(40)
    }

    private func errorView(_ msg: String) -> some View {
        ContentUnavailableView("No Results", systemImage: "globe.slash",
                               description: Text(msg))
        .foregroundStyle(.white)
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(vm.records.count) record\(vm.records.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().background(Color.white.opacity(0.08))

            ForEach(vm.records) { record in
                DNSRecordRow(record: record, color: vm.selectedType.color)
                if record.id != vm.records.last?.id {
                    Divider().background(Color.white.opacity(0.06)).padding(.leading, 16)
                }
            }
        }
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - DNS Record Row

private struct DNSRecordRow: View {
    let record: DNSRecord
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(record.type)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                if let ttl = record.ttl {
                    Text("TTL \(ttl)s")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.30))
                }
            }

            Text(record.value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        DNSLookupView()
    }
}
