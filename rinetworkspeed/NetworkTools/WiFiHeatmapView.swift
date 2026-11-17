//
//  WiFiHeatmapView.swift
//  rinetworkspeed
//
//  Heatmap list, creation (photo of a floor plan or a blank grid) and the
//  editor where the user taps their position on the plan to measure there.
//

import SwiftUI
import PhotosUI

/// Navigation value for a heatmap, separate from the UUIDs other tools push.
struct HeatmapRoute: Hashable {
    let id: UUID
}

private let heatmapTint = Color(red: 0.93, green: 0.42, blue: 0.20)

// MARK: - List

struct WiFiHeatmapListView: View {
    @ObservedObject private var store = WiFiHeatmapStore.shared
    @State private var showingNew = false
    @State private var opened: HeatmapRoute?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                heroCard

                if store.surveys.isEmpty {
                    AppEmptyState(
                        icon: "map",
                        title: "No Heatmaps Yet",
                        message: "Add a photo of your floor plan, or use a blank grid, then measure in different spots around your home."
                    )
                    .appCard(padding: nil)
                } else {
                    AppSection("Heatmaps") {
                        ForEach(store.surveys) { survey in
                            NavigationLink(value: HeatmapRoute(id: survey.id)) {
                                AppRow(icon: "map.fill", tint: heatmapTint, verbatimTitle: survey.name,
                                       subtitle: "\(survey.points.count) measurements") {
                                    AppChevron()
                                }
                            }
                            .buttonStyle(AppRowButtonStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.delete(id: survey.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            if survey.id != store.surveys.last?.id {
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
        .navigationTitle("Wi-Fi Heatmap")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: HeatmapRoute.self) { route in
            WiFiHeatmapEditorView(surveyID: route.id)
        }
        .navigationDestination(item: $opened) { route in
            WiFiHeatmapEditorView(surveyID: route.id)
        }
        .sheet(isPresented: $showingNew) {
            NewHeatmapSheet { survey in
                opened = HeatmapRoute(id: survey.id)
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("See Wi-Fi Across Your Home")
                    .appFont(size: 22, weight: .bold, design: .rounded)
                    .foregroundStyle(AppTheme.ink)
                Text("Tap where you stand on the plan; RiNetwork measures there and colours the map between your spots.")
                    .appFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                showingNew = true
            } label: {
                Label("New Heatmap", systemImage: "plus")
            }
            .buttonStyle(AppPrimaryButtonStyle(variant: .inverted, tint: heatmapTint))
        }
        .appHeroCard(tint: heatmapTint)
    }
}

// MARK: - New heatmap

private struct NewHeatmapSheet: View {
    let onCreate: (WiFiHeatmapSurvey) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var plan: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Home", text: $name)
                }
                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(plan == nil ? "Choose a Floor Plan Photo" : "Choose Another Photo", systemImage: "photo")
                    }
                    if let plan {
                        Image(uiImage: plan)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                        Button("Use a Blank Grid Instead", role: .destructive) {
                            self.plan = nil
                            photoItem = nil
                        }
                    }
                } footer: {
                    Text("A photo or screenshot of a floor plan works best. Without one, a blank grid is used; you can still place spots roughly where they are.")
                }
            }
            .navigationTitle("New Heatmap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        let survey = WiFiHeatmapStore.shared.create(
                            named: trimmed.isEmpty ? String(localized: "Home") : trimmed,
                            plan: plan
                        )
                        dismiss()
                        onCreate(survey)
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        plan = Self.downscaled(image, maxSide: 2_000)
                    }
                }
            }
        }
    }

    /// Keeps stored plans small; a phone photo can be 12 MP.
    private static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Editor

struct WiFiHeatmapEditorView: View {
    let surveyID: UUID

    private enum TapMode: Hashable {
        case measure
        case router
    }

    @ObservedObject private var store = WiFiHeatmapStore.shared
    @ObservedObject private var signalStore = WiFiSignalStore.shared
    @StateObject private var measurer = HeatmapMeasurer()
    @State private var metric: HeatmapMetric = .router
    @State private var mode: TapMode = .measure
    @AppStorage("heatmapIncludesDownload") private var includeDownload = true
    @AppStorage("heatmapIncludesSignal") private var includeSignal = false
    @State private var pendingSpot: CGPoint?
    @State private var selectedPointID: UUID?
    @State private var showingNotOnWiFi = false
    @State private var planImage: UIImage?

    private var survey: WiFiHeatmapSurvey? { store.survey(id: surveyID) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if let survey {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    planView(survey)
                    statusLine
                    controls(survey)
                    adviceCard(survey)
                    legend
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .appPageBackground()
        .navigationTitle(survey?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let survey { planImage = store.planImage(for: survey) }
            if signalStore.latest == nil { includeSignal = false }
        }
        .alert("Not on Wi-Fi", isPresented: $showingNotOnWiFi) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Join the Wi-Fi network you want to map, then try again.")
        }
        .sheet(item: Binding(
            get: { selectedPointID.flatMap { id in survey?.points.first { $0.id == id } } },
            set: { selectedPointID = $0?.id }
        )) { point in
            HeatmapPointSheet(point: point) {
                removePoint(point.id)
                selectedPointID = nil
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: Plan

    private func planView(_ survey: WiFiHeatmapSurvey) -> some View {
        let samples = survey.samples(for: metric)
        let suggestion = HeatmapMath.meshSuggestion(router: survey.router, samples: samples)

        return GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                if let planImage {
                    Image(uiImage: planImage)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                } else {
                    GridBackground()
                }

                HeatmapLayer(samples: samples, aspectRatio: survey.planAspectRatio)

                ForEach(survey.points) { point in
                    let score = metric.score(point, bestDownload: survey.bestDownload)
                    Circle()
                        .fill(score.map { HeatmapLevel(score: $0).color } ?? AppTheme.ink.opacity(0.3))
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .frame(width: 18, height: 18)
                        .position(x: point.x * size.width, y: point.y * size.height)
                }

                if let router = survey.router {
                    marker(systemName: "wifi.router.fill", color: AppTheme.download)
                        .position(x: router.x * size.width, y: router.y * size.height)
                }

                if let suggestion {
                    marker(systemName: "plus", color: AppTheme.ping)
                        .position(x: suggestion.x * size.width, y: suggestion.y * size.height)
                        .accessibilityLabel(Text("Suggested spot for a mesh point"))
                }

                if let pendingSpot, measurer.isMeasuring {
                    ProgressView()
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .position(x: pendingSpot.x * size.width, y: pendingSpot.y * size.height)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                handleTap(at: location, in: size, survey: survey)
            }
        }
        .aspectRatio(survey.planAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.cardStroke, lineWidth: 1)
        )
    }

    private func marker(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

    private func handleTap(at location: CGPoint, in size: CGSize, survey: WiFiHeatmapSurvey) {
        guard size.width > 0, size.height > 0 else { return }
        let x = min(1, max(0, location.x / size.width))
        let y = min(1, max(0, location.y / size.height))

        if mode == .router {
            var updated = survey
            updated.routerX = x
            updated.routerY = y
            store.update(updated)
            mode = .measure
            return
        }

        // A tap on an existing spot opens it instead of measuring again.
        if let hit = survey.points.first(where: {
            hypot(($0.x - x) * size.width, ($0.y - y) * size.height) < 22
        }) {
            selectedPointID = hit.id
            return
        }

        guard !measurer.isMeasuring else { return }
        pendingSpot = CGPoint(x: x, y: y)
        Task {
            let point = await measurer.measure(at: x, y: y, includeDownload: includeDownload,
                                               includeSignal: includeSignal && signalStore.latest != nil)
            pendingSpot = nil
            guard let point else {
                showingNotOnWiFi = true
                return
            }
            // Re-read: the survey may have changed while measuring.
            guard var current = store.survey(id: surveyID) else { return }
            current.points.append(point)
            store.update(current)
        }
    }

    private func removePoint(_ id: UUID) {
        guard var current = store.survey(id: surveyID) else { return }
        current.points.removeAll { $0.id == id }
        store.update(current)
    }

    // MARK: Controls

    private var statusLine: some View {
        HStack(spacing: 8) {
            if measurer.isMeasuring {
                ProgressView().scaleEffect(0.8)
            } else {
                Image(systemName: mode == .router ? "wifi.router" : "hand.tap")
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Text(statusText)
                .appFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var statusText: LocalizedStringKey {
        switch measurer.phase {
        case .router: return "Measuring the Wi-Fi link to the router…"
        case .download: return "Running a short download…"
        case .signal: return "Reading the Wi-Fi signal…"
        case .idle:
            return mode == .router
                ? "Tap where your router is."
                : "Stand still, then tap where you are on the plan."
        }
    }

    private func controls(_ survey: WiFiHeatmapSurvey) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Tap to", selection: $mode) {
                Text("Measure").tag(TapMode.measure)
                Text("Mark Router").tag(TapMode.router)
            }
            .pickerStyle(.segmented)

            Picker("Show", selection: $metric) {
                Text("Router").tag(HeatmapMetric.router)
                Text("Download").tag(HeatmapMetric.download)
                Text("Signal").tag(HeatmapMetric.signal)
            }
            .pickerStyle(.segmented)

            VStack(spacing: 0) {
                Toggle(isOn: $includeDownload) {
                    Text("Short download at each spot (3 s)")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                AppRowDivider(leadingInset: 16)
                Toggle(isOn: $includeSignal) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wi-Fi signal at each spot")
                        if signalStore.latest == nil {
                            Text("Set up signal reading in the Wi-Fi details first.")
                                .appFont(size: 12, weight: .regular, design: .rounded)
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                    }
                }
                .disabled(signalStore.latest == nil)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .appFont(size: 14, weight: .medium, design: .rounded)
            .tint(heatmapTint)
            .appCard(padding: nil)
        }
        .disabled(measurer.isMeasuring)
    }

    // MARK: Advice

    private func adviceCard(_ survey: WiFiHeatmapSurvey) -> some View {
        let samples = survey.samples(for: metric)
        let weakest = samples.min { $0.score < $1.score }
        let best = samples.max { $0.score < $1.score }

        return VStack(alignment: .leading, spacing: 8) {
            if samples.isEmpty {
                if survey.points.isEmpty {
                    Text("Measure in at least three spots: near the router, in the middle of your home and in the room where Wi-Fi is worst.")
                } else {
                    Text("No spot has this value yet. Measure with it turned on, or choose another view.")
                }
            } else {
                if let best, let weakest, samples.count > 1 {
                    Text("Best spot: \(Text(HeatmapLevel(score: best.score).title)). Weakest spot: \(Text(HeatmapLevel(score: weakest.score).title)).")
                }
                if HeatmapMath.meshSuggestion(router: survey.router, samples: samples) != nil {
                    Text("The green + marks halfway between the router and the weakest spot: a good place to try a mesh point or to move the router towards. This is a rule of thumb; walls and floors matter more than distance.")
                } else if survey.router == nil {
                    Text("Use Mark Router to show where your router is and get a placement suggestion.")
                } else if let weakest, weakest.score >= 0.5 {
                    Text("Every measured spot is at least good.")
                }
            }
        }
        .appFont(size: 14, weight: .regular, design: .rounded)
        .foregroundStyle(AppTheme.primaryText)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(HeatmapLevel.allCases.reversed(), id: \.self) { level in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(level.color).frame(width: 14, height: 14)
                    Text(level.title)
                }
            }
        }
        .appFont(size: 12, weight: .medium, design: .rounded)
        .foregroundStyle(AppTheme.secondaryText)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Layers

/// Coloured cells between measured spots; spots further than the reach of
/// any measurement stay uncoloured.
private struct HeatmapLayer: View {
    let samples: [(x: Double, y: Double, score: Double)]
    let aspectRatio: Double

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }
            let columns = 48
            let rows = max(1, Int((Double(columns) / max(aspectRatio, 0.1)).rounded()))
            let cell = CGSize(width: size.width / CGFloat(columns), height: size.height / CGFloat(rows))
            for row in 0..<rows {
                for column in 0..<columns {
                    let x = (Double(column) + 0.5) / Double(columns)
                    let y = (Double(row) + 0.5) / Double(rows)
                    guard let score = HeatmapMath.interpolate(x: x, y: y, samples: samples, aspectRatio: aspectRatio) else { continue }
                    let rect = CGRect(x: CGFloat(column) * cell.width, y: CGFloat(row) * cell.height,
                                      width: cell.width + 0.5, height: cell.height + 0.5)
                    context.fill(Path(rect), with: .color(HeatmapLevel(score: score).color.opacity(0.45)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct GridBackground: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(AppTheme.cardFill))
            let step = max(size.width, size.height) / 12
            var path = Path()
            var x: CGFloat = step
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = step
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(AppTheme.separator), lineWidth: 1)
        }
    }
}

// MARK: - Point details

private struct HeatmapPointSheet: View {
    let point: HeatmapPoint
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            List {
                row("Measured", point.date.formatted(date: .abbreviated, time: .shortened))
                row("Router round trip", point.routerLatency.map { "\($0.fixed(1)) ms" })
                row("Router jitter", point.routerJitter.map { "\($0.fixed(1)) ms" })
                row("Router loss", point.routerLoss.formatted(.percent.precision(.fractionLength(0))))
                row("Download", point.downloadMbps.map { "\($0.fixed(1)) Mbps" })
                row("Signal strength", point.rssi.map { "\($0) dBm" })
                Section {
                    Button("Delete This Spot", role: .destructive, action: onDelete)
                }
            }
            .navigationTitle("Spot")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Level styling

extension HeatmapLevel {
    var color: Color {
        switch self {
        case .excellent: return AppTheme.ping
        case .good: return Color(red: 0.6, green: 0.85, blue: 0.2)
        case .fair: return AppTheme.warning
        case .weak: return AppTheme.danger
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .weak: return "Weak"
        }
    }
}
