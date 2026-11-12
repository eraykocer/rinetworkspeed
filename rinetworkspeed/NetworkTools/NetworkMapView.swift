//
//  NetworkMapView.swift
//  rinetworkspeed
//
//  Created by Codex on 10.04.2026.
//

import SwiftUI

// MARK: - Main View

struct NetworkMapView: View {
    @StateObject private var manager = NetworkMapManager()

    @State private var selectedDevice: MapDevice?
    @State private var appeared: Set<UUID>  = []
    @State private var showList: Bool       = false

    // Zoom / pan
    @State private var totalScale: CGFloat  = 1.0
    @State private var gestureScale: CGFloat = 1.0
    @State private var panOffset: CGSize    = .zero
    @State private var gestureDelta: CGSize = .zero

    // Canvas size (captured from GeometryReader)
    @State private var canvasSize: CGSize   = .zero

    private let heroColors = [Color(red: 0.20, green: 0.80, blue: 0.65),
                              Color(red: 0.08, green: 0.45, blue: 0.52)]

    var body: some View {
        NavigationStack {
            Group {
                if showList {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            heroCard
                            NetworkMapListView(manager: manager, selectedDevice: $selectedDevice)
                        }
                        .padding(.horizontal, AppTheme.pagePadding)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                } else {
                    // Map mode stays non-scrolling so pan/zoom gestures own the canvas.
                    VStack(spacing: 16) {
                        heroCard
                        mapCard
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .appPageBackground()
            .navigationTitle("Network Map")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedDevice) { device in
                MapDeviceDetailSheet(device: device, manager: manager)
            }
        }
        .appPageBackground()
        .task {
            if manager.devices.isEmpty && !manager.isScanning {
                appeared = []
                await manager.scan()
            }
        }
        .onAppear {
            appeared = Set(manager.devices.map(\.id))
        }
        .onChange(of: manager.isScanning) { _, scanning in
            if scanning { appeared = [] }
        }
        .onChange(of: manager.devices) { _, newDevices in
            let fresh = newDevices.filter { !appeared.contains($0.id) }
            for dev in fresh {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.65)) {
                    _ = appeared.insert(dev.id)
                }
            }
        }
    }

    // MARK: – Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("Visually discover devices on the local network")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            summaryStrip

            HStack(spacing: 10) {
                // Rescan
                Button {
                    Task { await manager.scan() }
                } label: {
                    HStack(spacing: 8) {
                        if manager.isScanning {
                            ProgressView()
                                .tint(heroColors[1])
                                .scaleEffect(0.85)
                            Text("Scanning…")
                        } else {
                            Image(systemName: "arrow.clockwise")
                            Text("Rescan")
                        }
                    }
                }
                .buttonStyle(AppPrimaryButtonStyle(variant: .inverted, colors: heroColors))
                .disabled(manager.isScanning)

                // List / Map toggle
                Button {
                    withAnimation(.spring(response: 0.32)) { showList.toggle() }
                } label: {
                    Image(systemName: showList ? "circle.hexagongrid.fill" : "list.bullet")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(.white.opacity(0.18)))
                }
                .buttonStyle(AppPressableButtonStyle())
                .accessibilityLabel(showList ? Text("Map") : Text("List"))
            }
        }
        .appHeroCard(colors: heroColors)
    }

    private var summaryStrip: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                MapHeroStat(value: "\(manager.devices.count)", label: "Devices")
                AppMetricDivider()
                if manager.isScanning {
                    MapHeroStat(value: "\(Int(manager.progress * 100))%", label: "Scanning…")
                } else if let date = manager.lastScanDate {
                    MapHeroStat(value: date.formatted(date: .omitted, time: .shortened), label: "Last scan")
                } else {
                    MapHeroStat(value: "–", label: "Last scan")
                }
            }

            // Scan progress strip
            if manager.isScanning {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.18))
                        Capsule()
                            .fill(.white)
                            .frame(width: g.size.width * manager.progress)
                            .animation(.linear(duration: 0.2), value: manager.progress)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 12)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: – Map card

    private var mapCard: some View {
        GeometryReader { geo in
            mapCanvas
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { _, s in canvasSize = s }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.cardFill)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    // MARK: – Canvas map

    private var mapCanvas: some View {
        ZStack {
            // Animated connections + dot grid (TimelineView drives dash phase)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { ctx, size in
                    drawDotGrid(ctx: ctx, size: size)
                    let phase  = timeline.date.timeIntervalSinceReferenceDate
                    let dPhase = CGFloat(phase.truncatingRemainder(dividingBy: 1.0) * -28)
                    drawConnections(ctx: ctx, size: size, dashPhase: dPhase, phase: phase)
                }
            }

            // Interactive node overlays
            ForEach(manager.devices) { device in
                MapNodeView(
                    device: device,
                    isSelected: selectedDevice?.id == device.id,
                    isRouter: isRouterDevice(device)
                )
                .position(transformedPos(for: device, in: canvasSize))
                .scaleEffect(appeared.contains(device.id) ? 1.0 : 0.01)
                .animation(
                    .spring(response: 0.40, dampingFraction: 0.65),
                    value: appeared.contains(device.id)
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.28)) {
                        selectedDevice = selectedDevice?.id == device.id ? nil : device
                    }
                }
            }

            // Empty state
            if manager.devices.isEmpty && !manager.isScanning {
                AppEmptyState(icon: "wifi.slash", title: "No scan performed", message: "Tap Rescan")
            }
        }
        .clipShape(Rectangle())
        .gesture(magnifyGesture)
        .simultaneousGesture(dragGesture)
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.38)) {
                totalScale = 1.0
                gestureScale = 1.0
                panOffset = .zero
                gestureDelta = .zero
            }
        }
    }

    // MARK: – Gestures

    private var displayScale: CGFloat  { totalScale * gestureScale }
    private var displayOffset: CGSize  {
        CGSize(width:  panOffset.width  + gestureDelta.width,
               height: panOffset.height + gestureDelta.height)
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { v in
                gestureScale = max(0.4, min(5.0, v))
            }
            .onEnded { v in
                totalScale   = max(0.4, min(5.0, totalScale * v))
                gestureScale = 1.0
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in gestureDelta = v.translation }
            .onEnded { v in
                panOffset = CGSize(
                    width:  panOffset.width  + v.translation.width,
                    height: panOffset.height + v.translation.height
                )
                gestureDelta = .zero
            }
    }

    // MARK: – Position helpers

    private func isRouterDevice(_ device: MapDevice) -> Bool {
        device.deviceType == .router || device.ip == manager.routerIP
    }

    private var centerDevice: MapDevice? {
        manager.devices.first(where: { isRouterDevice($0) })
            ?? manager.devices.first
    }

    private func naturalPos(for device: MapDevice, in size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        guard size.width > 0 else { return center }

        if let center_device = centerDevice, device.id == center_device.id {
            return center
        }

        let peripherals = manager.devices.filter {
            guard let hub = centerDevice else { return true }
            return $0.id != hub.id
        }

        let total = max(1, peripherals.count)
        let idx   = peripherals.firstIndex(where: { $0.id == device.id }) ?? 0
        let radius: CGFloat = min(size.width, size.height) * 0.32
        let angle = 2 * .pi * Double(idx) / Double(total) - .pi / 2

        return CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
    }

    private func transformedPos(for device: MapDevice, in size: CGSize) -> CGPoint {
        let nat    = naturalPos(for: device, in: size)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let s      = displayScale
        let o      = displayOffset
        return CGPoint(
            x: center.x + (nat.x - center.x) * s + o.width,
            y: center.y + (nat.y - center.y) * s + o.height
        )
    }

    // MARK: – Canvas drawing

    private func drawDotGrid(ctx: GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 28
        let dotR: CGFloat    = 1.4
        var path = Path()
        var x: CGFloat = 0
        while x <= size.width { defer { x += spacing }
            var y: CGFloat = 0
            while y <= size.height { defer { y += spacing }
                path.addEllipse(in: CGRect(x: x - dotR, y: y - dotR,
                                           width: dotR * 2, height: dotR * 2))
            }
        }
        ctx.fill(path, with: .color(Color.white.opacity(0.055)))
    }

    private func drawConnections(ctx: GraphicsContext, size: CGSize,
                                  dashPhase: CGFloat, phase: Double) {
        guard let hub = centerDevice, size.width > 0 else { return }
        let hubPos = transformedPos(for: hub, in: size)
        let s      = displayScale

        // Router pulse rings (canvas-driven, no SwiftUI animation needed)
        let routerColor  = MapDeviceType.router.nodeColor
        let routerRadius = (isRouterDevice(hub) ? 32.0 : 22.0) * Double(s)
        let phaseMod = phase.truncatingRemainder(dividingBy: 2.0) / 2.0  // 0…1
        for i in 0..<2 {
            let ring     = routerRadius * (1.0 + Double(i) * 0.5 + phaseMod * 0.55)
            let opacity  = max(0, 0.55 - phaseMod * 0.55 - Double(i) * 0.18)
            let ringPath = Path(ellipseIn: CGRect(
                x: hubPos.x - ring, y: hubPos.y - ring,
                width: ring * 2,   height: ring * 2
            ))
            ctx.stroke(ringPath,
                       with: .color(routerColor.opacity(opacity)),
                       lineWidth: 1.5)
        }

        // Connection lines from hub to each peripheral
        for device in manager.devices where device.id != hub.id {
            guard appeared.contains(device.id) else { continue }
            let devPos  = transformedPos(for: device, in: size)
            let rt      = device.responseTime
            let color   = lineColorFor(ms: rt)
            let lw      = lineWidthFor(ms: rt) * s
            let dash: [CGFloat] = [6 * s, 5 * s]

            var linePath = Path()
            linePath.move(to: hubPos)
            linePath.addLine(to: devPos)
            ctx.stroke(linePath,
                       with: .color(color),
                       style: StrokeStyle(
                           lineWidth: lw,
                           lineCap: .round,
                           dash: dash,
                           dashPhase: dashPhase * s
                       ))
        }
    }

    private func lineColorFor(ms: Double) -> Color {
        if ms <= 0  { return Color(red: 59/255, green: 130/255, blue: 246/255).opacity(0.6) }
        if ms < 5   { return Color(red: 52/255,  green: 211/255, blue: 153/255) }
        if ms < 20  { return Color(red: 234/255, green: 179/255, blue: 8/255) }
        return Color(red: 239/255, green: 68/255, blue: 68/255)
    }

    private func lineWidthFor(ms: Double) -> CGFloat {
        if ms <= 0 { return 1.8 }
        if ms < 5  { return 2.2 }
        if ms < 20 { return 1.7 }
        return 1.2
    }
}

// MARK: - MapNodeView

private struct MapNodeView: View {
    let device: MapDevice
    let isSelected: Bool
    let isRouter: Bool

    private var nodeSize: CGFloat { isRouter ? 64 : 46 }
    private var color: Color      { device.deviceType.nodeColor }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                // Current device glow
                if device.isCurrentDevice {
                    Circle()
                        .fill(color.opacity(0.22))
                        .blur(radius: 10)
                        .frame(width: nodeSize * 1.6, height: nodeSize * 1.6)
                }

                // Main circle
                Circle()
                    .fill(color.opacity(0.14))
                    .overlay(
                        Circle().stroke(
                            device.isCurrentDevice ? color : color.opacity(0.44),
                            lineWidth: device.isCurrentDevice ? 2.5 : 1.5
                        )
                    )
                    .frame(width: nodeSize, height: nodeSize)
                    .shadow(
                        color: color.opacity(isRouter ? 0.55 : 0.2),
                        radius: isRouter ? 18 : 8
                    )

                // Icon
                Image(systemName: device.deviceType.rawValue)
                    .font(.system(size: nodeSize * 0.38, weight: .semibold))
                    .foregroundStyle(color)

                // Selection ring
                if isSelected {
                    Circle()
                        .stroke(.white, lineWidth: 2.5)
                        .frame(width: nodeSize + 8, height: nodeSize + 8)
                }
            }

            // Last IP octet label
            let lastOctet = device.ip.split(separator: ".").last.map(String.init) ?? device.ip
            Text(lastOctet)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.65)))
        }
    }
}

// MARK: - Hero Stat

/// Value + caption pair shown inside the hero summary strip.
private struct MapHeroStat: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - List View

private struct NetworkMapListView: View {
    @ObservedObject var manager: NetworkMapManager
    @Binding var selectedDevice: MapDevice?

    var body: some View {
        if manager.devices.isEmpty {
            AppEmptyState(icon: "network", title: "No Devices Found", message: "Tap Rescan")
                .appCard(padding: nil)
        } else {
            AppSection("Devices") {
                ForEach(manager.devices) { device in
                    Button { selectedDevice = device } label: {
                        MapListRow(device: device)
                    }
                    .buttonStyle(AppRowButtonStyle())

                    if device.id != manager.devices.last?.id {
                        AppRowDivider()
                    }
                }
            }
        }
    }
}

private struct MapListRow: View {
    let device: MapDevice

    var body: some View {
        HStack(spacing: 14) {
            AppIconTile(systemName: device.deviceType.rawValue, tint: device.deviceType.nodeColor)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.hostname ?? device.ip)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                    if device.isCurrentDevice {
                        AppPill(text: "This device", tint: device.deviceType.nodeColor)
                    }
                }
                if device.hostname != nil {
                    Text(device.ip)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if device.responseTime > 0 {
                    AppPill(text: "\(Int(device.responseTime.rounded())) ms", tint: latencyColor(device.responseTime))
                        .monospacedDigit()
                }
                Text(device.deviceType.displayName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(1)
            }

            AppChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func latencyColor(_ ms: Double) -> Color {
        if ms < 5  { return AppTheme.ping }
        if ms < 20 { return AppTheme.warning }
        return AppTheme.danger
    }
}

// MARK: - Device Detail Sheet

private struct MapDeviceDetailSheet: View {
    let device: MapDevice
    let manager: NetworkMapManager

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    header

                    AppSection("Device Info") {
                        infoRow("IP Address", value: device.ip)
                        if let h = device.hostname {
                            AppRowDivider(leadingInset: 16)
                            infoRow("Hostname", value: h)
                        }
                        if let mac = device.macAddress {
                            AppRowDivider(leadingInset: 16)
                            infoRow("MAC Address", value: mac)
                        }
                        AppRowDivider(leadingInset: 16)
                        infoRow("Device Type", value: device.deviceType.displayName)
                        if device.responseTime > 0 {
                            AppRowDivider(leadingInset: 16)
                            infoRow("Response Time", value: String(format: "%.1f ms", device.responseTime))
                        }
                        if device.isCurrentDevice {
                            AppRowDivider(leadingInset: 16)
                            infoRow("Durum", value: String(localized: "This Device"))
                        }
                    }

                    AppSection("Actions") {
                        NavigationLink {
                            PortScannerView(initialHost: device.ip)
                        } label: {
                            AppRow(
                                icon: "door.left.hand.open",
                                tint: Color(red: 0.84, green: 0.28, blue: 0.74),
                                title: "Scan Ports"
                            ) {
                                AppChevron()
                            }
                        }
                        .buttonStyle(AppRowButtonStyle())

                        AppRowDivider()

                        NavigationLink {
                            PingMonitorView(
                                monitor: PingMonitor(),
                                initialHost: device.ip
                            )
                        } label: {
                            AppRow(icon: "timer", tint: AppTheme.ping, title: "Monitor Ping") {
                                AppChevron()
                            }
                        }
                        .buttonStyle(AppRowButtonStyle())
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .appPageBackground()
            .navigationTitle(device.hostname ?? device.ip)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .presentationBackground(AppTheme.background)
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppIconTile(systemName: device.deviceType.rawValue, tint: device.deviceType.nodeColor, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.hostname ?? device.ip)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                Text(device.deviceType.displayName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 8)

            if device.isCurrentDevice {
                AppPill(text: "This device", tint: device.deviceType.nodeColor)
            }
        }
        .padding(.top, 8)
    }

    private func infoRow(_ label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

#Preview {
    NetworkMapView()
        .preferredColorScheme(.dark)
}
