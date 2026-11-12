//
//  WakeOnLANView.swift
//  rinetworkspeed
//
//  Wake-on-LAN: sends a "magic packet" (6 × 0xFF followed by the target MAC
//  address 16 times) as a UDP broadcast on the local network.
//
//  iOS only allows apps to send broadcast packets when Apple has granted them
//  the multicast networking entitlement (com.apple.developer.networking.multicast).
//  Without it the send fails, and the user is told why.
//

import SwiftUI
import Combine
import Darwin

struct WakeDevice: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var mac: String
    var broadcast: String
    var port: UInt16 = 9
}

nonisolated enum MagicPacket {
    /// Six bytes from "AA:BB:CC:DD:EE:FF", "AA-BB-…" or "AABBCCDDEEFF".
    static func macBytes(_ mac: String) -> [UInt8]? {
        let hex = mac.filter(\.isHexDigit)
        guard hex.count == 12 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    static func packet(for mac: [UInt8]) -> [UInt8] {
        [UInt8](repeating: 0xFF, count: 6) + Array([[UInt8]](repeating: mac, count: 16).joined())
    }

    enum SendError: Error {
        case invalidMAC
        case invalidAddress
        /// The system refused the broadcast (no multicast entitlement, or not on Wi-Fi).
        case notPermitted(Int32)
        case failed(Int32)
    }

    /// Sends the packet with a BSD socket, because Network.framework connections
    /// cannot enable SO_BROADCAST.
    static func send(to device: WakeDevice) throws {
        guard let mac = macBytes(device.mac) else { throw SendError.invalidMAC }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = device.port.bigEndian
        guard inet_pton(AF_INET, device.broadcast, &address.sin_addr) == 1 else { throw SendError.invalidAddress }

        let socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { throw SendError.failed(errno) }
        defer { close(socketFD) }

        var enable: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))

        let payload = packet(for: mac)
        let sent = payload.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socketFD, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == payload.count else {
            let code = errno
            if code == EHOSTUNREACH || code == EPERM || code == EACCES || code == ENETUNREACH {
                throw SendError.notPermitted(code)
            }
            throw SendError.failed(code)
        }
    }
}

@MainActor
final class WakeDeviceStore: ObservableObject {
    static let shared = WakeDeviceStore()

    @Published private(set) var devices: [WakeDevice] = []
    private let defaultsKey = "wakeOnLANDevices"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let stored = try? JSONDecoder().decode([WakeDevice].self, from: data) {
            devices = stored
        }
    }

    func add(_ device: WakeDevice) {
        devices.append(device)
        save()
    }

    func delete(id: UUID) {
        devices.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

struct WakeOnLANView: View {
    @ObservedObject private var store = WakeDeviceStore.shared
    @State private var showingAdd = false
    @State private var message: (text: String, isError: Bool)?

    private let tint = Color(red: 0.98, green: 0.62, blue: 0.16)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                if let message {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(message.isError ? AppTheme.warning : AppTheme.ping)
                        Text(verbatim: message.text)
                            .appFont(size: 13, weight: .medium, design: .rounded)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .appCard()
                }

                if store.devices.isEmpty {
                    AppEmptyState(
                        icon: "power",
                        title: "No Devices",
                        message: "Add a computer with its MAC address to turn it on from your iPhone. Wake-on-LAN must be enabled on the computer."
                    )
                    .appCard(padding: nil)
                } else {
                    AppSection("Devices", footer: "Touch and hold a device to delete it.") {
                        ForEach(store.devices) { device in
                            AppRow(icon: "desktopcomputer", tint: tint, verbatimTitle: device.name, subtitle: LocalizedStringKey(stringLiteral: device.mac.uppercased())) {
                                Button("Wake") { wake(device) }
                                    .appFont(size: 14, weight: .semibold, design: .rounded)
                                    .foregroundStyle(tint)
                            }
                            .contextMenu {
                                Button(role: .destructive) { store.delete(id: device.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            if device.id != store.devices.last?.id {
                                AppRowDivider()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .appPageBackground()
        .navigationTitle("Wake-on-LAN")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Label("Add Device", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddWakeDeviceSheet { store.add($0) }
        }
    }

    private func wake(_ device: WakeDevice) {
        do {
            try MagicPacket.send(to: device)
            message = (String(localized: "Magic packet sent to \(device.name)."), false)
        } catch MagicPacket.SendError.notPermitted {
            message = (String(localized: "iOS blocked the broadcast. Sending Wake-on-LAN packets requires a permission Apple grants to the app separately; make sure you are also on the same Wi-Fi as the computer."), true)
        } catch MagicPacket.SendError.invalidMAC {
            message = (String(localized: "The MAC address is not valid."), true)
        } catch MagicPacket.SendError.invalidAddress {
            message = (String(localized: "The broadcast address is not valid."), true)
        } catch {
            message = (String(localized: "The packet could not be sent."), true)
        }
    }
}

private struct AddWakeDeviceSheet: View {
    let onSave: (WakeDevice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var mac = ""
    @State private var broadcast = AddWakeDeviceSheet.defaultBroadcast()

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && MagicPacket.macBytes(mac) != nil
            && SubnetCalculation.parse(broadcast) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name, e.g. Office PC", text: $name)
                TextField("MAC address, e.g. AA:BB:CC:DD:EE:FF", text: $mac)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Section {
                    TextField("Broadcast address", text: $broadcast)
                        .keyboardType(.numbersAndPunctuation)
                } footer: {
                    Text("Usually the last address of your network, e.g. 192.168.1.255.")
                }
            }
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(WakeDevice(name: name.trimmingCharacters(in: .whitespaces), mac: mac, broadcast: broadcast))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Broadcast address of the current Wi-Fi subnet, or a common default.
    private static func defaultBroadcast() -> String {
        let details = WiFiInfoManager.localInterfaceDetails()
        if let ip = details.ipAddress,
           let prefix = details.subnetMask.flatMap(SubnetCalculation.prefix(fromMask:)),
           let calculation = SubnetCalculation("\(ip)/\(prefix)") {
            return SubnetCalculation.format(calculation.broadcast)
        }
        return "192.168.1.255"
    }
}

#Preview {
    NavigationStack {
        WakeOnLANView()
    }
}
