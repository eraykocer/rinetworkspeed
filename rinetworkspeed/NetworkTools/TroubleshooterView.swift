//
//  TroubleshooterView.swift
//  rinetworkspeed
//
//  One-tap connection check: network → router → DNS → internet → latency.
//  The first step that fails decides the plain-language diagnosis.
//

import SwiftUI
import Network
import Combine

// MARK: - Model

enum DiagnosticStepKind: Int, CaseIterable, Identifiable {
    case network
    case router
    case dns
    case internet
    case latency

    var id: Int { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .network: return "Network Connection"
        case .router: return "Router"
        case .dns: return "DNS (Name Lookup)"
        case .internet: return "Internet Access"
        case .latency: return "Latency & Stability"
        }
    }

    var icon: String {
        switch self {
        case .network: return "wifi"
        case .router: return "wifi.router.fill"
        case .dns: return "globe"
        case .internet: return "network"
        case .latency: return "waveform.path.ecg"
        }
    }
}

enum DiagnosticStatus: Equatable {
    case pending
    case running
    case passed
    case warning
    case failed
    case skipped
}

struct DiagnosticStep: Identifiable {
    let kind: DiagnosticStepKind
    var status: DiagnosticStatus = .pending
    var detail: String?

    var id: DiagnosticStepKind { kind }
}

struct Diagnosis {
    let title: LocalizedStringResource
    let advice: String
    let status: DiagnosticStatus
}

// MARK: - View Model

@MainActor
final class TroubleshooterViewModel: ObservableObject {
    @Published private(set) var steps = DiagnosticStepKind.allCases.map { DiagnosticStep(kind: $0) }
    @Published private(set) var isRunning = false
    @Published private(set) var diagnosis: Diagnosis?

    private var task: Task<Void, Never>?

    func run() {
        task?.cancel()
        steps = DiagnosticStepKind.allCases.map { DiagnosticStep(kind: $0) }
        diagnosis = nil
        isRunning = true

        task = Task {
            await runSteps()
            isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
        isRunning = false
    }

    private func update(_ kind: DiagnosticStepKind, _ status: DiagnosticStatus, _ detail: String? = nil) {
        steps[kind.rawValue].status = status
        steps[kind.rawValue].detail = detail
    }

    private func skipRemaining(after kind: DiagnosticStepKind) {
        for step in DiagnosticStepKind.allCases where step.rawValue > kind.rawValue {
            update(step, .skipped)
        }
    }

    private func runSteps() async {
        // 1. Network
        update(.network, .running)
        let path = await Self.currentPath()
        guard path.status == .satisfied else {
            update(.network, .failed, String(localized: "No Wi-Fi, cellular or wired connection."))
            skipRemaining(after: .network)
            diagnosis = Diagnosis(
                title: "You're offline",
                advice: String(localized: "Turn on Wi-Fi or mobile data and check that Airplane Mode is off."),
                status: .failed
            )
            return
        }
        let isLocalNetwork = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
        update(.network, .passed, isLocalNetwork ? String(localized: "Connected over Wi-Fi.") : String(localized: "Connected over cellular."))
        guard !Task.isCancelled else { return }

        // 2. Router (only meaningful on Wi-Fi or wired)
        if isLocalNetwork, let gateway = WiFiInfoManager.localInterfaceDetails().routerIP {
            update(.router, .running)
            if let ms = await Self.reachability(host: gateway) {
                update(.router, .passed, String(localized: "\(gateway) answered in \(ms.fixed(0)) ms."))
            } else {
                update(.router, .failed, String(localized: "\(gateway) did not answer."))
                skipRemaining(after: .router)
                diagnosis = Diagnosis(
                    title: "Your router isn't responding",
                    advice: String(localized: "Move closer to the router or restart it. If other devices have no internet either, the router or modem is the likely cause."),
                    status: .failed
                )
                return
            }
        } else {
            update(.router, .skipped, String(localized: "Not applicable on cellular."))
        }
        guard !Task.isCancelled else { return }

        // 3. DNS
        update(.dns, .running)
        guard let dnsTime = await Self.resolve(host: "www.apple.com") else {
            update(.dns, .failed, String(localized: "Could not look up www.apple.com."))
            skipRemaining(after: .dns)
            diagnosis = Diagnosis(
                title: "Name lookup (DNS) isn't working",
                advice: String(localized: "The network is up, but website names can't be found. Restart the router, or set a public DNS server such as 1.1.1.1 in the router or in the Wi-Fi settings on this iPhone."),
                status: .failed
            )
            return
        }
        update(.dns, dnsTime > 300 ? .warning : .passed, String(localized: "Resolved in \(dnsTime.fixed(0)) ms."))
        guard !Task.isCancelled else { return }

        // 4. Internet
        update(.internet, .running)
        switch await Self.checkInternet() {
        case .online(let ms):
            update(.internet, .passed, String(localized: "Reached apple.com in \(ms.fixed(0)) ms."))
        case .captivePortal:
            update(.internet, .failed, String(localized: "The network redirected the request to a login page."))
            skipRemaining(after: .internet)
            diagnosis = Diagnosis(
                title: "This network needs a sign-in",
                advice: String(localized: "Open Safari and complete the network's login page. This is common in hotels, cafés and airports."),
                status: .failed
            )
            return
        case .unreachable:
            update(.internet, .failed, String(localized: "Could not reach apple.com."))
            skipRemaining(after: .internet)
            diagnosis = Diagnosis(
                title: "The internet is unreachable",
                advice: String(localized: "Your device reaches the network but not the internet. This usually means an outage at your provider. Restart the modem, and contact your provider if it continues."),
                status: .failed
            )
            return
        }
        guard !Task.isCancelled else { return }

        // 5. Latency
        update(.latency, .running)
        var samples: [Double] = []
        var lost = 0
        for _ in 0..<5 {
            let ms = await PingMonitor.tcpConnectTime(host: "1.1.1.1", port: 443, timeout: 3)
            if ms >= 0 { samples.append(ms) } else { lost += 1 }
            guard !Task.isCancelled else { return }
        }

        guard !samples.isEmpty else {
            update(.latency, .failed, String(localized: "No response from 1.1.1.1."))
            diagnosis = Diagnosis(
                title: "The connection keeps dropping",
                advice: String(localized: "Websites load, but repeated connections fail. Restart the router and try again."),
                status: .failed
            )
            return
        }

        let average = samples.reduce(0, +) / Double(samples.count)
        let deltas = zip(samples.dropFirst(), samples).map { abs($0 - $1) }
        let jitter = deltas.isEmpty ? 0 : deltas.reduce(0, +) / Double(deltas.count)
        let detail = String(localized: "Average \(average.fixed(0)) ms, jitter \(jitter.fixed(0)) ms, \(lost) of 5 lost.")

        if average > 150 || jitter > 30 || lost > 0 {
            update(.latency, .warning, detail)
            diagnosis = Diagnosis(
                title: "Connected, but unstable",
                advice: String(localized: "High or uneven latency can make video calls and games stutter. Move closer to the router, use 5 GHz Wi-Fi if available, or pause large downloads on other devices."),
                status: .warning
            )
        } else {
            update(.latency, .passed, detail)
            diagnosis = Diagnosis(
                title: "Everything looks fine",
                advice: String(localized: "Your connection works from the router to the internet. If something still feels slow, run a speed test."),
                status: .passed
            )
        }
    }

    // MARK: Probes

    nonisolated private static func currentPath() async -> NWPath {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let once = OnceContinuation(continuation)
            monitor.pathUpdateHandler = { path in
                once.resume(path)
                monitor.cancel()
            }
            monitor.start(queue: DispatchQueue(label: "rinetworkspeed.troubleshooter.path"))
        }
    }

    /// Time until the host answered on a common port, in ms. A refused
    /// connection also counts: the device replied, it just has nothing listening.
    nonisolated private static func reachability(host: String) async -> Double? {
        for port: UInt16 in [80, 443, 53] {
            if let ms = await tcpAnswer(host: host, port: port) {
                return ms
            }
        }
        return nil
    }

    nonisolated private static func tcpAnswer(host: String, port: UInt16) async -> Double? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "rinetworkspeed.troubleshooter.tcp")

        return await withCheckedContinuation { continuation in
            let once = OnceContinuation<Double?>(continuation)
            let start = DispatchTime.now().uptimeNanoseconds
            let elapsed = { Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.resume(elapsed())
                    connection.cancel()
                case .failed(let error), .waiting(let error):
                    if case .posix(let code) = error, code == .ECONNREFUSED {
                        once.resume(elapsed())
                    } else {
                        once.resume(nil)
                    }
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 2) {
                once.resume(nil)
                connection.cancel()
            }
        }
    }

    /// Lookup time in ms, or nil if the name could not be resolved within 5 s.
    nonisolated private static func resolve(host: String) async -> Double? {
        await withCheckedContinuation { continuation in
            let once = OnceContinuation<Double?>(continuation)
            let start = DispatchTime.now().uptimeNanoseconds

            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_socktype = SOCK_STREAM
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(host, nil, &hints, &result)
                if result != nil { freeaddrinfo(result) }
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                once.resume(status == 0 ? ms : nil)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                once.resume(nil)
            }
        }
    }

    private enum InternetResult {
        case online(Double)
        case captivePortal
        case unreachable
    }

    /// Apple's captive-portal test page returns a page containing "Success".
    /// A portal either serves its own page or breaks the TLS handshake.
    nonisolated private static func checkInternet() async -> InternetResult {
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else { return .unreachable }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let (data, _) = try await session.data(from: url)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            let body = String(decoding: data, as: UTF8.self)
            return body.contains("Success") ? .online(ms) : .captivePortal
        } catch let error as URLError {
            switch error.code {
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid, .secureConnectionFailed, .appTransportSecurityRequiresSecureConnection:
                return .captivePortal
            default:
                return .unreachable
            }
        } catch {
            return .unreachable
        }
    }
}

// MARK: - View

struct TroubleshooterView: View {
    @StateObject private var vm = TroubleshooterViewModel()

    private let tint = Color(red: 0.36, green: 0.30, blue: 0.86)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                heroCard

                if let diagnosis = vm.diagnosis {
                    diagnosisCard(diagnosis)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                AppSection("Checks") {
                    ForEach(vm.steps) { step in
                        stepRow(step)
                        if step.kind != DiagnosticStepKind.allCases.last {
                            AppRowDivider()
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .animation(.easeInOut(duration: 0.25), value: vm.diagnosis?.advice)
        }
        .appPageBackground()
        .navigationTitle("Troubleshooter")
        .toolReport(vm) { $0.reportText }
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vm.cancel() }
        #if DEBUG
        .onAppear {
            // UI review helper: launch with `-debugRunTroubleshooter YES`.
            if UserDefaults.standard.bool(forKey: "debugRunTroubleshooter"), !vm.isRunning, vm.diagnosis == nil {
                vm.run()
            }
        }
        #endif
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connection Troubleshooter")
                    .appFont(size: 22, weight: .bold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)
                Text("Checks your router, DNS and internet access step by step and explains what is wrong.")
                    .appFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Button {
                vm.isRunning ? vm.cancel() : vm.run()
            } label: {
                HStack(spacing: 8) {
                    if vm.isRunning {
                        ProgressView().tint(tint)
                        Text("Stop")
                    } else {
                        Image(systemName: "stethoscope")
                        Text(vm.diagnosis == nil ? "Run Diagnosis" : "Run Again")
                    }
                }
            }
            .buttonStyle(AppPrimaryButtonStyle(variant: .inverted, tint: tint))
        }
        .appHeroCard(tint: tint)
    }

    private func diagnosisCard(_ diagnosis: Diagnosis) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol(for: diagnosis.status))
                .appFont(size: 26, weight: .semibold)
                .foregroundStyle(color(for: diagnosis.status))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(diagnosis.title)
                    .appFont(size: 17, weight: .bold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)
                Text(verbatim: diagnosis.advice)
                    .appFont(size: 14, weight: .regular, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appCard()
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(color(for: diagnosis.status).opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func stepRow(_ step: DiagnosticStep) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AppIconTile(systemName: step.kind.icon, tint: step.status == .skipped ? .gray : tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.kind.title)
                    .appFont(size: 16, weight: .semibold, design: .rounded)
                    .foregroundStyle(step.status == .skipped ? AppTheme.tertiaryText : AppTheme.primaryText)
                if let detail = step.detail {
                    Text(verbatim: detail)
                        .appFont(size: 12, weight: .regular, design: .rounded)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Group {
                if step.status == .running {
                    ProgressView()
                } else {
                    Image(systemName: symbol(for: step.status))
                        .appFont(size: 20, weight: .semibold)
                        .foregroundStyle(color(for: step.status))
                }
            }
            .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(accessibilityStatus(step.status)))
    }

    private func symbol(for status: DiagnosticStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .running: return "circle.dotted"
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle"
        }
    }

    private func color(for status: DiagnosticStatus) -> Color {
        switch status {
        case .passed: return AppTheme.ping
        case .warning: return AppTheme.warning
        case .failed: return AppTheme.danger
        default: return AppTheme.tertiaryText
        }
    }

    private func accessibilityStatus(_ status: DiagnosticStatus) -> LocalizedStringKey {
        switch status {
        case .pending: return "Not run"
        case .running: return "Checking"
        case .passed: return "Passed"
        case .warning: return "Warning"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        }
    }
}

#Preview {
    NavigationStack {
        TroubleshooterView()
    }
}
