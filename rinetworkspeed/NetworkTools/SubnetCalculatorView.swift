//
//  SubnetCalculatorView.swift
//  rinetworkspeed
//
//  IPv4 subnet calculator: network, broadcast, mask and host range for an
//  address in CIDR notation (e.g. 192.168.1.10/24).
//

import SwiftUI

/// Pure IPv4 subnet math, kept separate from the view so it can be unit tested.
nonisolated struct SubnetCalculation: Equatable, Sendable {
    let address: UInt32
    let prefix: Int

    /// Accepts "a.b.c.d/nn" or "a.b.c.d" (then `defaultPrefix` is used).
    init?(_ input: String, defaultPrefix: Int = 24) {
        let parts = input.trimmingCharacters(in: .whitespaces).split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let address = Self.parse(String(parts[0])) else { return nil }

        let prefix: Int
        if parts.count == 2 {
            guard let value = Int(parts[1]), (0...32).contains(value) else { return nil }
            prefix = value
        } else {
            prefix = defaultPrefix
        }
        self.address = address
        self.prefix = prefix
    }

    var mask: UInt32 { prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix) }
    var wildcard: UInt32 { ~mask }
    var network: UInt32 { address & mask }
    var broadcast: UInt32 { network | wildcard }
    var totalAddresses: UInt64 { UInt64(1) << UInt64(32 - prefix) }

    /// /31 and /32 have no separate network and broadcast addresses (RFC 3021).
    var usableHosts: UInt64 { prefix >= 31 ? totalAddresses : totalAddresses - 2 }
    var firstHost: UInt32 { prefix >= 31 ? network : network + 1 }
    var lastHost: UInt32 { prefix >= 31 ? broadcast : broadcast - 1 }

    var kind: LocalizedStringKey {
        let a = address >> 24, b = (address >> 16) & 0xFF
        if a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) { return "Private" }
        if a == 100 && (64...127).contains(b) { return "Carrier-grade NAT" }
        if a == 127 { return "Loopback" }
        if a == 169 && b == 254 { return "Link-local" }
        if (224...239).contains(a) { return "Multicast" }
        return "Public"
    }

    static func parse(_ string: String) -> UInt32? {
        let octets = string.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }
        var value: UInt32 = 0
        for octet in octets {
            guard let byte = UInt8(octet) else { return nil }
            value = value << 8 | UInt32(byte)
        }
        return value
    }

    static func format(_ value: UInt32) -> String {
        [24, 16, 8, 0].map { String((value >> UInt32($0)) & 0xFF) }.joined(separator: ".")
    }

    /// Prefix length for a dotted mask such as 255.255.255.0, if it is contiguous.
    static func prefix(fromMask mask: String) -> Int? {
        guard let value = parse(mask) else { return nil }
        let ones = value.nonzeroBitCount
        let expected: UInt32 = ones == 0 ? 0 : UInt32.max << UInt32(32 - ones)
        return value == expected ? ones : nil
    }
}

struct SubnetCalculatorView: View {
    @State private var input = ""

    private let tint = Color(red: 0.55, green: 0.42, blue: 0.98)

    private var calculation: SubnetCalculation? { SubnetCalculation(input) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                VStack(alignment: .leading, spacing: 10) {
                    AppInputField(icon: "number", placeholder: "IP/prefix, e.g. 192.168.1.10/24", text: $input, keyboard: .numbersAndPunctuation)
                    Text("Without a prefix, /24 is used.")
                        .appFont(size: 12, weight: .regular, design: .rounded)
                        .foregroundStyle(AppTheme.tertiaryText)
                        .padding(.horizontal, 4)
                }

                if let c = calculation {
                    AppSection("Subnet") {
                        row("Network", SubnetCalculation.format(c.network) + "/\(c.prefix)")
                        AppRowDivider(leadingInset: 16)
                        row("Subnet Mask", SubnetCalculation.format(c.mask))
                        AppRowDivider(leadingInset: 16)
                        row("Wildcard Mask", SubnetCalculation.format(c.wildcard))
                        AppRowDivider(leadingInset: 16)
                        row("Broadcast", SubnetCalculation.format(c.broadcast))
                    }

                    AppSection("Hosts") {
                        row("First Host", SubnetCalculation.format(c.firstHost))
                        AppRowDivider(leadingInset: 16)
                        row("Last Host", SubnetCalculation.format(c.lastHost))
                        AppRowDivider(leadingInset: 16)
                        row("Usable Hosts", c.usableHosts.formatted())
                        AppRowDivider(leadingInset: 16)
                        row("Total Addresses", c.totalAddresses.formatted())
                        AppRowDivider(leadingInset: 16)
                        HStack {
                            Text("Address Type")
                                .appFont(size: 14, weight: .medium, design: .rounded)
                                .foregroundStyle(AppTheme.secondaryText)
                            Spacer()
                            Text(c.kind)
                                .appFont(size: 14, weight: .semibold, design: .rounded)
                                .foregroundStyle(AppTheme.primaryText)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                } else if !input.isEmpty {
                    AppEmptyState(icon: "exclamationmark.triangle", title: "Invalid address", message: "Use the form 192.168.1.10/24.")
                        .appCard(padding: nil)
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .appPageBackground()
        .navigationTitle("Subnet Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prefillCurrentNetwork)
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title)
                .appFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .appFont(size: 14, weight: .semibold, design: .monospaced)
                .foregroundStyle(AppTheme.primaryText)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    /// Starts with this device's Wi-Fi address and mask.
    private func prefillCurrentNetwork() {
        guard input.isEmpty else { return }
        let details = WiFiInfoManager.localInterfaceDetails()
        guard let ip = details.ipAddress else { return }
        let prefix = details.subnetMask.flatMap(SubnetCalculation.prefix(fromMask:)) ?? 24
        input = "\(ip)/\(prefix)"
    }
}

#Preview {
    NavigationStack {
        SubnetCalculatorView()
    }
}
