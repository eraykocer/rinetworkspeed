//
//  NetworkToolsView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI

// MARK: - Tool Descriptor

private struct NetworkToolDescriptor: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
    let gradientColors: [Color]
    let tag: Int
}

// MARK: - Main View

struct NetworkToolsView: View {
    private let backgroundColor = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private let tools: [NetworkToolDescriptor] = [
        .init(
            name: "IP Scanner",
            description: "Discover devices on local network",
            icon: "network",
            gradientColors: [Color(red: 0.24, green: 0.45, blue: 0.99),
                             Color(red: 0.12, green: 0.25, blue: 0.72)],
            tag: 0
        ),
        .init(
            name: "Traceroute",
            description: "Hop-by-hop path analysis",
            icon: "point.3.connected.trianglepath.dotted",
            gradientColors: [Color(red: 0.13, green: 0.72, blue: 0.52),
                             Color(red: 0.05, green: 0.41, blue: 0.30)],
            tag: 1
        ),
        .init(
            name: "DNS Lookup",
            description: "Query DNS records for any domain",
            icon: "globe.americas.fill",
            gradientColors: [Color(red: 0.98, green: 0.62, blue: 0.16),
                             Color(red: 0.78, green: 0.39, blue: 0.05)],
            tag: 2
        ),
        .init(
            name: "Port Scanner",
            description: "Check open TCP ports on a host",
            icon: "door.left.hand.open",
            gradientColors: [Color(red: 0.84, green: 0.28, blue: 0.74),
                             Color(red: 0.54, green: 0.12, blue: 0.48)],
            tag: 3
        ),
        .init(
            name: "SSL Checker",
            description: "Certificate validity & details",
            icon: "lock.shield.fill",
            gradientColors: [Color(red: 0.20, green: 0.75, blue: 0.99),
                             Color(red: 0.08, green: 0.40, blue: 0.72)],
            tag: 4
        ),
        .init(
            name: "Whois",
            description: "Domain registration information",
            icon: "doc.text.magnifyingglass",
            gradientColors: [Color(red: 0.99, green: 0.37, blue: 0.37),
                             Color(red: 0.72, green: 0.12, blue: 0.12)],
            tag: 5
        ),
        .init(
            name: "Network Map",
            description: "Visually discover devices on the local network",
            icon: "circle.hexagongrid.fill",
            gradientColors: [Color(red: 0.20, green: 0.80, blue: 0.65),
                             Color(red: 0.06, green: 0.46, blue: 0.38)],
            tag: 6
        ),
        .init(
            name: "Speed Test",
            description: "Measure ping, download and upload speed",
            icon: "gauge.with.dots.needle.67percent",
            gradientColors: [Color(red: 0.16, green: 0.47, blue: 0.96),
                             Color(red: 0.42, green: 0.22, blue: 0.93)],
            tag: 7
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(tools) { tool in
                        NavigationLink {
                            destinationView(for: tool.tag)
                        } label: {
                            ToolCard(tool: tool)
                        }
                        .buttonStyle(ToolCardButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Network Tools")
        }
        .background(backgroundColor.ignoresSafeArea())
    }

    @ViewBuilder
    private func destinationView(for tag: Int) -> some View {
        switch tag {
        case 0: IPScannerView()
        case 1: TracerouteView()
        case 2: DNSLookupView()
        case 3: PortScannerView()
        case 4: SSLCheckerView()
        case 5: WhoisView()
        case 6: NetworkMapView()
        case 7: SpeedTestView(manager: SpeedTestManager())
        default: EmptyView()
        }
    }
}

// MARK: - Tool Card

private struct ToolCard: View {
    let tool: NetworkToolDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                LinearGradient(
                    colors: tool.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Image(systemName: tool.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(tool.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(tool.description)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [tool.gradientColors[0].opacity(0.18),
                         tool.gradientColors[1].opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [tool.gradientColors[0].opacity(0.50),
                                 tool.gradientColors[1].opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: tool.gradientColors[0].opacity(0.20), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Button Style

private struct ToolCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

#Preview {
    NetworkToolsView()
}
