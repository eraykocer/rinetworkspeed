//
//  WiFiSafetyView.swift
//  rinetworkspeed
//
//  "Is this Wi-Fi safe?": encryption, interception of secure connections,
//  DNS redirection, other devices that can reach this iPhone, and whether the
//  network looks like the one seen under the same name before (evil twin).
//

import SwiftUI
import Combine
import NetworkExtension
import Security

// MARK: - Pure checks

nonisolated enum TLSRoots {
    /// Words found in the names of widely trusted public root certificates.
    /// Interception proxies use their own roots (company, antivirus or attacker).
    static let publicRootWords = [
        "gts root", "google", "isrg", "digicert", "globalsign", "sectigo", "comodo", "usertrust",
        "aaa certificate services", "baltimore", "entrust", "amazon", "starfield", "go daddy", "godaddy",
        "apple", "microsoft", "quovadis", "certum", "ssl.com", "identrust", "buypass", "harica",
        "t-telesec", "actalis", "swisssign", "certainly", "telia", "trustasia", "hellenic", "izenpe",
        "secom", "cybertrust", "verisign", "thawte", "geotrust", "e-tugra", "kamu sm", "tubitak"
    ]

    static func isPublic(rootName: String) -> Bool {
        let lowered = rootName.lowercased()
        return publicRootWords.contains { lowered.contains($0) }
    }
}

/// What was seen on a Wi-Fi name before, to notice a look-alike network.
nonisolated struct KnownWiFi: Codable, Equatable, Sendable {
    var gateways: Set<String> = []
    var accessPoints: Set<String> = []

    nonisolated enum Change: Equatable, Sendable {
        case firstVisit
        case same
        /// Same router, another access point: normal for mesh and large networks.
        case newAccessPoint
        /// Another router address under the same name.
        case differentRouter
    }

    func compare(gateway: String?, accessPoint: String?) -> Change {
        guard !gateways.isEmpty || !accessPoints.isEmpty else { return .firstVisit }
        if let gateway, !gateways.isEmpty, !gateways.contains(gateway) { return .differentRouter }
        if let accessPoint, !accessPoints.contains(accessPoint.lowercased()) { return .newAccessPoint }
        return .same
    }

    mutating func record(gateway: String?, accessPoint: String?) {
        if let gateway { gateways.insert(gateway) }
        if let accessPoint { accessPoints.insert(accessPoint.lowercased()) }
    }
}

// MARK: - Results

struct SafetyCheck: Identifiable, Equatable {
    enum Kind: Int {
        case encryption, interception, dns, neighbours, lookAlike
    }

    var id: Kind { kind }
    let kind: Kind
    let status: CheckStatus
    let title: String
    let detail: String
}

// MARK: - ViewModel

@MainActor
final class WiFiSafetyViewModel: ObservableObject {
    @Published private(set) var checks: [SafetyCheck] = []
    @Published private(set) var isRunning = false
    @Published private(set) var notOnWiFi = false

    private var task: Task<Void, Never>?
    private static let memoryKey = "knownWiFiNetworks"

    var verdict: CheckStatus? {
        guard !checks.isEmpty, !isRunning else { return nil }
        if checks.contains(where: { $0.status == .fail }) { return .fail }
        if checks.contains(where: { $0.status == .warning }) { return .warning }
        return .pass
    }

    func start() {
        task?.cancel()
        checks = []
        notOnWiFi = false
        isRunning = true
        task = Task {
            defer { isRunning = false }
            let details = WiFiInfoManager.localInterfaceDetails()
            guard let own = details.ipAddress else {
                notOnWiFi = true
                return
            }
            let network = await NEHotspotNetwork.fetchCurrent()

            let encryption = encryptionCheck(network)
            add(encryption)
            add(await interceptionCheck())
            add(await dnsCheck())
            add(await neighboursCheck(own: own, gateway: details.routerIP, isOpen: network?.securityType == .open))
            add(lookAlikeCheck(network: network, gateway: details.routerIP))
        }
    }

    func cancel() {
        task?.cancel()
        isRunning = false
    }

    private func add(_ check: SafetyCheck) {
        guard !Task.isCancelled else { return }
        checks.append(check)
    }

    // MARK: Checks

    private func encryptionCheck(_ network: NEHotspotNetwork?) -> SafetyCheck {
        let title = String(localized: "Wi-Fi encryption")
        guard let network else {
            return SafetyCheck(kind: .encryption, status: .info, title: title,
                               detail: String(localized: "Allow location access in the Wi-Fi details to see the security type; iOS only shares it then."))
        }
        switch network.securityType {
        case .open:
            return SafetyCheck(kind: .encryption, status: .fail, title: title,
                               detail: String(localized: "Open network: anyone nearby can read traffic that isn't encrypted by the app or website itself. Use a VPN or mobile data for anything private."))
        case .WEP:
            return SafetyCheck(kind: .encryption, status: .fail, title: title,
                               detail: String(localized: "WEP is broken and can be cracked in minutes. Change the router to WPA2 or WPA3."))
        case .personal, .enterprise:
            return SafetyCheck(kind: .encryption, status: .pass, title: title,
                               detail: String(localized: "The connection to the router is encrypted (WPA)."))
        default:
            return SafetyCheck(kind: .encryption, status: .info, title: title,
                               detail: String(localized: "iOS didn't report the security type."))
        }
    }

    private func interceptionCheck() async -> SafetyCheck {
        let title = String(localized: "Secure connections")
        let hosts = ["www.apple.com", "www.google.com", "www.cloudflare.com"]
        var results: [TLSInspector.Result] = []
        for host in hosts {
            if let result = await TLSInspector.inspect(host: host) { results.append(result) }
        }
        guard !results.isEmpty else {
            return SafetyCheck(kind: .interception, status: .info, title: title,
                               detail: String(localized: "Couldn't reach the test websites."))
        }
        if results.contains(where: { !$0.trusted }) {
            return SafetyCheck(kind: .interception, status: .fail, title: title,
                               detail: String(localized: "A website presented a certificate iOS doesn't trust. This network may be redirecting to a login page, or intercepting connections. Don't enter passwords here."))
        }
        let unknownRoots = results.compactMap(\.rootName).filter { !TLSRoots.isPublic(rootName: $0) }
        if let root = unknownRoots.first, unknownRoots.count >= 2 {
            return SafetyCheck(kind: .interception, status: .warning, title: title,
                               detail: String(localized: "Secure connections are signed by “\(root)”, not by a public certificate authority. On a company or school network this is usually a security filter; on public Wi-Fi it can mean someone is reading your traffic."))
        }
        return SafetyCheck(kind: .interception, status: .pass, title: title,
                           detail: String(localized: "Websites present their own certificates; nothing reads secure connections in between."))
    }

    private func dnsCheck() async -> SafetyCheck {
        let title = String(localized: "Name lookups (DNS)")
        // A name that cannot exist must not resolve.
        let probe = "\(UUID().uuidString.lowercased().prefix(12)).example.com"
        let resolved = await TracerouteViewModel.resolveHost(probe)
        if let resolved {
            return SafetyCheck(kind: .dns, status: .warning, title: title,
                               detail: String(localized: "A made-up website name led to \(resolved). This network or your provider redirects lookups, often to ad or login pages. An encrypted DNS (see DNS Benchmark) avoids it."))
        }
        return SafetyCheck(kind: .dns, status: .pass, title: title,
                           detail: String(localized: "Lookups for names that don't exist fail, as they should."))
    }

    private func neighboursCheck(own: String, gateway: String?, isOpen: Bool) async -> SafetyCheck {
        let title = String(localized: "Other devices")
        let found = await DeviceFingerprinter.discoverAnnouncements(interfaceAddress: own, duration: 3)
        let others = found.keys.filter { $0 != own && $0 != gateway }.count
        if others == 0 {
            return SafetyCheck(kind: .neighbours, status: .pass, title: title,
                               detail: String(localized: "No other devices announced themselves, so the network probably keeps devices apart."))
        }
        return SafetyCheck(kind: .neighbours, status: isOpen ? .warning : .info, title: title,
                           detail: isOpen
                               ? String(localized: "\(others) other devices are visible, so they can reach this iPhone too. On public Wi-Fi, turn off file and screen sharing.")
                               : String(localized: "\(others) other devices are visible. That's normal at home; on public Wi-Fi it means others can reach this iPhone."))
    }

    private func lookAlikeCheck(network: NEHotspotNetwork?, gateway: String?) -> SafetyCheck {
        let title = String(localized: "Same network as before")
        guard let ssid = network?.ssid else {
            return SafetyCheck(kind: .lookAlike, status: .info, title: title,
                               detail: String(localized: "Allow location access to compare this network with earlier visits."))
        }
        var memory = Self.loadMemory()
        var known = memory[ssid] ?? KnownWiFi()
        let change = known.compare(gateway: gateway, accessPoint: network?.bssid)
        known.record(gateway: gateway, accessPoint: network?.bssid)
        memory[ssid] = known
        Self.saveMemory(memory)

        switch change {
        case .firstVisit:
            return SafetyCheck(kind: .lookAlike, status: .info, title: title,
                               detail: String(localized: "First check of “\(ssid)”. Next time, a different router under this name will be pointed out."))
        case .same:
            return SafetyCheck(kind: .lookAlike, status: .pass, title: title,
                               detail: String(localized: "“\(ssid)” has the same router as on earlier checks."))
        case .newAccessPoint:
            return SafetyCheck(kind: .lookAlike, status: .info, title: title,
                               detail: String(localized: "Same router, another access point. That's normal for mesh systems and large networks."))
        case .differentRouter:
            return SafetyCheck(kind: .lookAlike, status: .warning, title: title,
                               detail: String(localized: "“\(ssid)” now has a different router address than before. If the network wasn't changed, this may be a fake network using the same name."))
        }
    }

    private static func loadMemory() -> [String: KnownWiFi] {
        guard let data = UserDefaults.standard.data(forKey: memoryKey),
              let memory = try? JSONDecoder().decode([String: KnownWiFi].self, from: data) else { return [:] }
        return memory
    }

    private static func saveMemory(_ memory: [String: KnownWiFi]) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        UserDefaults.standard.set(data, forKey: memoryKey)
    }
}

/// Opens an HTTPS connection and reports whether iOS trusts the certificate
/// and which root it chains to.
nonisolated final class TLSInspector: NSObject, URLSessionDelegate, @unchecked Sendable {
    nonisolated struct Result: Sendable {
        let trusted: Bool
        let rootName: String?
    }

    private let lock = NSLock()
    private var result: Result?

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let trusted = SecTrustEvaluateWithError(trust, nil)
        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        let root = chain.last.flatMap { SecCertificateCopySubjectSummary($0) as String? }
        lock.lock()
        result = Result(trusted: trusted, rootName: root)
        lock.unlock()
        completionHandler(.performDefaultHandling, nil)
    }

    static func inspect(host: String) async -> Result? {
        guard let url = URL(string: "https://\(host)/") else { return nil }
        let inspector = TLSInspector()
        let session = URLSession(configuration: .ephemeral, delegate: inspector, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 6
        _ = try? await session.data(for: request)
        inspector.lock.lock()
        defer { inspector.lock.unlock() }
        return inspector.result
    }
}

// MARK: - View

struct WiFiSafetyView: View {
    @StateObject private var vm = WiFiSafetyViewModel()
    private let tint = Color(red: 0.16, green: 0.62, blue: 0.40)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                ToolHero(icon: "lock.shield.fill", title: "Is This Wi-Fi Safe?",
                         subtitle: "Checks encryption, interception of secure connections, DNS redirection, other devices and look-alike networks.",
                         tint: tint, isRunning: vm.isRunning, startTitle: "Check This Wi-Fi") {
                    vm.isRunning ? vm.cancel() : vm.start()
                }

                if vm.notOnWiFi {
                    NoteCard(status: .warning, title: Text("Not on Wi-Fi"),
                             message: Text("Join the Wi-Fi network you want to check."))
                }

                if let verdict = vm.verdict {
                    switch verdict {
                    case .fail:
                        NoteCard(status: .fail, title: Text("Be careful on this network"),
                                 message: Text("Avoid logins and payments here, or use mobile data or a VPN."))
                    case .warning:
                        NoteCard(status: .warning, title: Text("Mostly fine, with something to look at"),
                                 message: Text("Read the points marked below."))
                    default:
                        NoteCard(status: .pass, title: Text("No problems found"),
                                 message: Text("Nothing suspicious in these checks. Websites and apps still need their own encryption, which almost all have."))
                    }
                }

                if !vm.checks.isEmpty || vm.isRunning {
                    AppSection("Checks") {
                        ForEach(vm.checks) { check in
                            CheckRow(status: check.status, title: Text(verbatim: check.title), detail: Text(verbatim: check.detail))
                            if check.id != vm.checks.last?.id || vm.isRunning { AppRowDivider(leadingInset: 16) }
                        }
                        if vm.isRunning {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Checking…").foregroundStyle(AppTheme.secondaryText)
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .appPageBackground()
        .navigationTitle("Wi-Fi Safety")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vm.cancel() }
    }
}
