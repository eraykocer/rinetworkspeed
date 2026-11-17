//
//  TracerouteView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//
//  Real TTL-based traceroute that keeps measuring every hop (MTR style) and
//  says where lasting packet loss starts.
//

import SwiftUI
import Network
import Darwin
import Combine

// MARK: - ViewModel

@MainActor
final class TracerouteViewModel: ObservableObject {
    @Published private(set) var hops: [RouteHop] = []
    @Published private(set) var isRunning = false
    @Published var targetHost: String = "google.com"
    @Published private(set) var errorMessage: String?
    @Published private(set) var finding: RouteFinding = .collecting
    /// Rounds completed in the current trace.
    @Published private(set) var rounds = 0
    /// Resolved address of `targetHost` for the current trace.
    @Published private(set) var targetAddress: String?

    static let maxHops = 30
    /// A probe without an answer after this long counts as lost.
    private let roundTimeout: TimeInterval = 1.5
    /// Shortest time between the starts of two rounds.
    private let roundInterval: TimeInterval = 1
    /// Stops on its own after about five minutes.
    private let maxRounds = 300

    private var traceTask: Task<Void, Never>?
    /// Lookups already started, by address.
    private var lookedUp: Set<String> = []
    private var hostnames: [String: String] = [:]
    private var networks: [String: ASNInfo] = [:]

    func start() {
        let target = targetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        traceTask?.cancel()
        isRunning = true
        hops = []
        rounds = 0
        finding = .collecting
        targetAddress = nil
        errorMessage = nil

        traceTask = Task {
            await runTrace(target: target)
            isRunning = false
        }
    }

    func cancel() {
        traceTask?.cancel()
        isRunning = false
    }

    // MARK: - Trace Pipeline

    private func runTrace(target: String) async {
        guard let address = await Self.resolveHost(target) else {
            errorMessage = String(localized: "Could not resolve \(target)")
            return
        }
        targetAddress = address

        guard let tracer = ICMPTracer(destination: address) else {
            errorMessage = String(localized: "This device could not open a traceroute socket.")
            return
        }

        var table: [Int: RouteHop] = [:]
        var destinationTTL: Int?
        var probeLimit = Self.maxHops

        for round in 0..<maxRounds {
            guard !Task.isCancelled else { return }
            let started = ProcessInfo.processInfo.systemUptime

            let replies = await tracer.round(ttls: 1...probeLimit, timeout: roundTimeout)
            guard !Task.isCancelled else { return }

            // Every probe past the destination reaches it too, so the lowest
            // TTL with an echo reply is the destination's distance.
            if destinationTTL == nil,
               let reached = replies.filter({ $0.value.reachedDestination }).keys.min() {
                destinationTTL = reached
                probeLimit = reached
                table = table.filter { $0.key <= reached }
            }

            for ttl in 1...probeLimit {
                table[ttl, default: RouteHop(ttl: ttl)].record(replies[ttl])
            }

            let highestAnswered = table.values.filter { $0.received > 0 }.map(\.ttl).max()
            if destinationTTL == nil, round == 0 {
                // The destination does not answer: keep probing a little past
                // the last router that did.
                probeLimit = min(Self.maxHops, (highestAnswered ?? 0) + 3)
                table = table.filter { $0.key <= probeLimit }
            }
            if highestAnswered == nil, round >= 2 {
                errorMessage = String(localized: "No hop answered. This network may block traceroute.")
                hops = []
                return
            }

            let displayLimit = destinationTTL ?? min(probeLimit, (highestAnswered ?? 0) + 1)
            hops = (1...displayLimit).compactMap { table[$0] }.map(applyLookups)
            rounds = round + 1
            finding = RouteFinding.evaluate(hops)
            startLookups(for: hops)

            let elapsed = ProcessInfo.processInfo.systemUptime - started
            if elapsed < roundInterval {
                try? await Task.sleep(nanoseconds: UInt64((roundInterval - elapsed) * 1_000_000_000))
            }
        }
    }

    // MARK: - Names and networks

    private func applyLookups(_ hop: RouteHop) -> RouteHop {
        guard let address = hop.address else { return hop }
        var hop = hop
        hop.hostname = hostnames[address]
        hop.asn = networks[address]
        return hop
    }

    /// Reverse DNS for every new address and the network operator for public
    /// ones; results show up from the next round.
    private func startLookups(for hops: [RouteHop]) {
        for address in hops.compactMap(\.address) where !lookedUp.contains(address) {
            lookedUp.insert(address)
            Task { [weak self] in
                async let name = IPScannerViewModel.reverseDNS(address)
                async let network = ASNLookup.lookup(address)
                let (hostname, asn) = await (name, network)
                guard let self else { return }
                if let hostname { self.hostnames[address] = hostname }
                if let asn { self.networks[address] = asn }
            }
        }
    }

    // MARK: - DNS Resolution

    static func resolveHost(_ hostname: String) async -> String? {
        await Task.detached(priority: .utility) {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_STREAM
            var res: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(hostname, nil, &hints, &res) == 0, let first = res else { return nil }
            defer { freeaddrinfo(res) }
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var sa = first.pointee.ai_addr!.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            guard inet_ntop(AF_INET, &sa.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buf)
        }.value
    }
}

// MARK: - Main View

struct TracerouteView: View {
    @StateObject private var vm = TracerouteViewModel()
    private let accent = Color(red: 0.13, green: 0.72, blue: 0.52)
    private let accentDeep = Color(red: 0.05, green: 0.41, blue: 0.30)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                heroCard

                if let err = vm.errorMessage {
                    ToolErrorCard(title: "Trace Failed", message: err)
                } else if !vm.hops.isEmpty {
                    RouteFindingCard(finding: vm.finding, rounds: vm.rounds)
                    hopsSection
                } else if vm.isRunning {
                    AppSection {
                        progressRow(Text("Tracing the route…"))
                    }
                } else {
                    AppEmptyState(
                        icon: "point.3.connected.trianglepath.dotted",
                        title: "No Trace Yet",
                        message: "Enter a host and start a trace to see each hop along the route."
                    )
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .appPageBackground()
        .navigationTitle("Traceroute")
        .toolReport(vm) { $0.reportText }
        .navigationBarTitleDisplayMode(.large)
        .onDisappear { vm.cancel() }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            ToolHeroHeader(
                icon: "point.3.connected.trianglepath.dotted",
                title: "Hop-by-hop path analysis",
                subtitle: "Finds every hop to a host and keeps measuring loss and latency at each one."
            )

            AppInputField(icon: "globe", placeholder: "Target host (e.g. google.com)", text: $vm.targetHost, showsFavorites: true) {
                if !vm.isRunning { vm.start() }
            }
            .heroInset()

            Button {
                vm.isRunning ? vm.cancel() : vm.start()
            } label: {
                HStack(spacing: 8) {
                    if vm.isRunning {
                        ProgressView().tint(accentDeep)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(vm.isRunning ? "Stop Trace" : "Start Trace")
                }
            }
            .buttonStyle(AppPrimaryButtonStyle(variant: .inverted, tint: accentDeep))
        }
        .appHeroCard(tint: accentDeep)
    }

    // MARK: - Hops Section

    private var hopsSection: some View {
        AppSection("Route", footer: "Loss at one hop that does not continue at the later hops is normal: many routers answer these probes slowly or not at all.") {
            ForEach(vm.hops) { hop in
                RouteHopRow(hop: hop, accent: accent)
                if hop.id != vm.hops.last?.id || vm.isRunning {
                    AppRowDivider()
                }
            }

            if vm.isRunning {
                progressRow(Text("Round \(vm.rounds)"))
            }
        }
    }

    private func progressRow(_ text: Text) -> some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(accent)
                .frame(width: 40, height: 40)
            text
                .appFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Finding

private struct RouteFindingCard: View {
    let finding: RouteFinding
    let rounds: Int

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AppIconTile(systemName: icon, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                // `title` and `message` are already `Text`.
                title
                    .appFont(size: 16, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)
                message
                    .appFont(size: 13, weight: .regular, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .appCard()
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch finding {
        case .collecting: return "hourglass"
        case .clean: return "checkmark"
        case .lossStarts: return "exclamationmark.triangle.fill"
        case .destinationSilent: return "questionmark"
        }
    }

    private var tint: Color {
        switch finding {
        case .collecting, .destinationSilent: return AppTheme.ink.opacity(0.35)
        case .clean: return AppTheme.ping
        case .lossStarts: return AppTheme.warning
        }
    }

    private var title: Text {
        switch finding {
        case .collecting:
            return Text("Measuring… (\(min(rounds, RouteFinding.minimumProbes)) of \(RouteFinding.minimumProbes) rounds)")
        case .clean:
            return Text("No lasting packet loss")
        case .lossStarts(let hop, _):
            return Text("Packet loss starts at hop \(hop)")
        case .destinationSilent:
            return Text("The destination doesn't answer")
        }
    }

    private var message: Text {
        switch finding {
        case .collecting:
            return Text("Each round sends one probe to every hop. Loss is judged after 10 rounds.")
        case .clean:
            return Text("Probes reach the destination without loss that lasts along the route.")
        case .lossStarts(_, .homeNetwork):
            return Text("The loss already starts at your router, so the problem is between this iPhone and the router: the Wi-Fi or the router itself.")
        case .lossStarts(_, .accessNetwork):
            return Text("The loss starts at a private address after your router: your provider's access network, or a second router in your home.")
        case .lossStarts(_, .provider(let network)):
            if let network {
                return Text("The loss starts inside your provider's network (\(network.label)). You can share this trace with your provider as evidence.")
            }
            return Text("The loss starts after your router, in your provider's network. You can share this trace with your provider as evidence.")
        case .lossStarts(_, .beyondProvider(let network)):
            return Text("The loss starts outside your provider's network, in \(network.label). Your provider may not be able to fix it.")
        case .destinationSilent:
            return Text("It doesn't reply to these probes, so loss to it can't be measured. The hops on the way are still shown; try 1.1.1.1 to test the route itself.")
        }
    }
}

// MARK: - Hop Row

private struct RouteHopRow: View {
    let hop: RouteHop
    let accent: Color

    private var answered: Bool { hop.received > 0 }

    private func latencyColor(_ ms: Double) -> Color {
        if ms < 20 { return AppTheme.ping }
        if ms < 80 { return Color(red: 0.6, green: 0.9, blue: 0.2) }
        if ms < 200 { return AppTheme.upload }
        return AppTheme.danger
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(verbatim: "\(hop.ttl)")
                .appFont(size: 16, weight: .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(answered ? .white : AppTheme.tertiaryText)
                .frame(width: 40, height: 40)
                .background(answered ? AnyShapeStyle(accent) : AnyShapeStyle(AppTheme.ink.opacity(0.06)),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: hop.hostname ?? hop.address ?? "* * *")
                    .appFont(size: 15, weight: .semibold, design: .rounded)
                    .foregroundStyle(answered ? AppTheme.primaryText : AppTheme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(verbatim: detail)
                        .appFont(size: 12, weight: .regular, design: .monospaced)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let average = hop.average {
                    Text(verbatim: average.fixed(1) + " ms")
                        .appFont(size: 13, weight: .semibold, design: .monospaced)
                        .foregroundStyle(latencyColor(average))
                } else {
                    Text(verbatim: "—")
                        .appFont(size: 13, weight: .semibold, design: .monospaced)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                Text(verbatim: hop.lossShare.formatted(.percent.precision(.fractionLength(0))))
                    .appFont(size: 11, weight: .bold, design: .rounded)
                    .foregroundStyle(hop.lossShare > 0 ? AppTheme.danger : AppTheme.secondaryText)
                    .accessibilityLabel(Text("Loss \(hop.lossShare.formatted(.percent.precision(.fractionLength(0))))"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    /// Address (when a name is shown) and network operator.
    private var detail: String? {
        var parts: [String] = []
        if hop.hostname != nil, let address = hop.address {
            parts.append(address)
        }
        if hop.addresses.count > 1 {
            parts.append("+\(hop.addresses.count - 1)")
        }
        if let network = hop.asn {
            parts.append(network.label)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

#Preview {
    NavigationStack {
        TracerouteView()
    }
    .preferredColorScheme(.dark)
}
