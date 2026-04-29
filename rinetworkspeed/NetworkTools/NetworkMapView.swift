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

    private let bg = Color(red: 10/255, green: 10/255, blue: 10/255)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                bg.ignoresSafeArea()

                if showList {
                    NetworkMapListView(manager: manager, selectedDevice: $selectedDevice)
                        .padding(.bottom, 72)
                } else {
                    GeometryReader { geo in
                        mapCanvas
                            .onAppear { canvasSize = geo.size }
                            .onChange(of: geo.size) { _, s in canvasSize = s }
                    }
                    .ignoresSafeArea(edges: .bottom)
                }

                bottomBar
            }
            .navigationTitle("Network Map")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedDevice) { device in
                MapDeviceDetailSheet(device: device, manager: manager)
            }
        }
        .background(bg.ignoresSafeArea())
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
                    appeared.insert(dev.id)
                }
            }
        }
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
                VStack(spacing: 14) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No scan performed")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("Tap Rescan")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.white.opacity(0.22))
                }
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

    // MARK: – Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(manager.devices.count) cihaz")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let date = manager.lastScanDate {
                    Text("Last scan: " + date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                } else if manager.isScanning {
                    Text("Scanning… \(Int(manager.progress * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .contentTransition(.numericText())
                }
            }

            Spacer()

            // List / Map toggle
            Button {
                withAnimation(.spring(response: 0.32)) { showList.toggle() }
            } label: {
                Image(systemName: showList ? "circle.hexagongrid.fill" : "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)

            // Rescan
            Button {
                Task { await manager.scan() }
            } label: {
                ZStack {
                    if manager.isScanning {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 42, height: 42)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 59/255, green: 130/255, blue: 246/255),
                                    Color(red: 168/255, green: 85/255,  blue: 247/255)
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(manager.isScanning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 0)
        )
        .overlay(alignment: .top) {
            // Scan progress strip
            if manager.isScanning {
                GeometryReader { g in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 59/255, green: 130/255, blue: 246/255),
                                    Color(red: 168/255, green: 85/255,  blue: 247/255)
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: g.size.width * manager.progress, height: 2)
                        .animation(.linear(duration: 0.2), value: manager.progress)
                }
                .frame(height: 2)
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

// MARK: - List View

private struct NetworkMapListView: View {
    @ObservedObject var manager: NetworkMapManager
    @Binding var selectedDevice: MapDevice?

    private let accentBlue = Color(red: 59/255, green: 130/255, blue: 246/255)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if manager.devices.isEmpty {
                    ContentUnavailableView(
                        "No Devices Found",
                        systemImage: "network",
                        description: Text("Tap Rescan")
                    )
                    .foregroundStyle(.white)
                    .padding(.top, 40)
                } else {
                    ForEach(manager.devices) { device in
                        Button { selectedDevice = device } label: {
                            MapListRow(device: device)
                        }
                        .buttonStyle(.plain)

                        if device.id != manager.devices.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.08))
                                .padding(.leading, 64)
                        }
                    }
                }
            }
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

private struct MapListRow: View {
    let device: MapDevice

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(device.deviceType.nodeColor.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: device.deviceType.rawValue)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(device.deviceType.nodeColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(device.hostname ?? device.ip)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if device.hostname != nil {
                    Text(device.ip)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }
                if device.isCurrentDevice {
                    Text("This device")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(device.deviceType.nodeColor)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if device.responseTime > 0 {
                    Text(String(format: "%.0f ms", device.responseTime))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(latencyColor(device.responseTime))
                }
                Text(device.deviceType.displayName)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.22))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func latencyColor(_ ms: Double) -> Color {
        if ms < 5  { return .green }
        if ms < 20 { return .yellow }
        return .red
    }
}

// MARK: - Device Detail Sheet

private struct MapDeviceDetailSheet: View {
    let device: MapDevice
    let manager: NetworkMapManager

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Device Info") {
                    infoRow("IP Address", value: device.ip)
                    if let h = device.hostname {
                        infoRow("Hostname", value: h)
                    }
                    if let mac = device.macAddress {
                        infoRow("MAC Address", value: mac)
                    }
                    infoRow("Device Type", value: device.deviceType.displayName)
                    if device.responseTime > 0 {
                        infoRow("Response Time", value: String(format: "%.1f ms", device.responseTime))
                    }
                    if device.isCurrentDevice {
                        infoRow("Durum", value: "This Device")
                    }
                }

                Section("Actions") {
                    NavigationLink {
                        PortScannerView(initialHost: device.ip)
                    } label: {
                        Label("Scan Ports", systemImage: "door.left.hand.open")
                    }

                    NavigationLink {
                        PingMonitorView(
                            monitor: PingMonitor(),
                            initialHost: device.ip
                        )
                    } label: {
                        Label("Monitor Ping", systemImage: "timer")
                    }
                }
            }
            .navigationTitle(device.hostname ?? device.ip)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, design: .monospaced))
        }
    }
}

#Preview {
    NetworkMapView()
}
