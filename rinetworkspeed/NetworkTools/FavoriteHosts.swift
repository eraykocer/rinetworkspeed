//
//  FavoriteHosts.swift
//  rinetworkspeed
//
//  Hosts the user checks often (router, a server, a game service), shared by
//  every tool that takes a host: Ping, Traceroute, Port Scanner, DNS, SSL and Whois.
//

import SwiftUI
import Combine

@MainActor
final class FavoriteHostsStore: ObservableObject {
    static let shared = FavoriteHostsStore()

    @Published private(set) var hosts: [String] = []

    private let defaultsKey = "favoriteHosts"

    private init() {
        hosts = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }

    func contains(_ host: String) -> Bool {
        hosts.contains(Self.normalized(host))
    }

    func toggle(_ host: String) {
        let value = Self.normalized(host)
        guard !value.isEmpty else { return }
        if let index = hosts.firstIndex(of: value) {
            hosts.remove(at: index)
        } else {
            hosts.insert(value, at: 0)
        }
        UserDefaults.standard.set(hosts, forKey: defaultsKey)
    }

    private static func normalized(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Star button for host fields: pick a favorite, or add / remove the current host.
struct FavoriteHostsMenu: View {
    @Binding var text: String
    @ObservedObject private var store = FavoriteHostsStore.shared

    private var current: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Menu {
            if !current.isEmpty {
                if store.contains(current) {
                    Button("Remove from Favorites", systemImage: "star.slash") { store.toggle(current) }
                } else {
                    Button("Add to Favorites", systemImage: "star") { store.toggle(current) }
                }
            }

            if store.hosts.isEmpty {
                Text("No favorites yet")
            } else {
                Section("Favorites") {
                    ForEach(store.hosts, id: \.self) { host in
                        Button {
                            text = host
                        } label: {
                            Text(verbatim: host)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: store.contains(current) ? "star.fill" : "star")
                .appFont(size: 16, weight: .semibold)
                .foregroundStyle(store.contains(current) ? AppTheme.warning : AppTheme.tertiaryText)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Favorite Hosts"))
    }
}
