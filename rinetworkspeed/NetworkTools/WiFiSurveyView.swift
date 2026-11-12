//
//  WiFiSurveyView.swift
//  rinetworkspeed
//
//  Room-by-room Wi-Fi survey: name the rooms, run a speed test in each and
//  see where coverage is best and worst. Survey tests are also saved to the
//  regular speed test history.
//

import SwiftUI
import Combine

// MARK: - Model

struct SurveyRoom: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// Bytes per second; nil until the room has been tested.
    var download: Double?
    var upload: Double?
    var ping: Double?
    var testedAt: Date?

    var downloadMbps: Double? { download.map { $0 * 8 / 1_000_000 } }
    var uploadMbps: Double? { upload.map { $0 * 8 / 1_000_000 } }
}

struct WiFiSurvey: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var rooms: [SurveyRoom] = []

    var testedRooms: [SurveyRoom] { rooms.filter { $0.download != nil } }

    var bestRoom: SurveyRoom? {
        testedRooms.max { ($0.download ?? 0) < ($1.download ?? 0) }
    }

    var worstRoom: SurveyRoom? {
        testedRooms.count > 1 ? testedRooms.min { ($0.download ?? 0) < ($1.download ?? 0) } : nil
    }
}

@MainActor
final class WiFiSurveyStore: ObservableObject {
    static let shared = WiFiSurveyStore()

    /// Newest first.
    @Published private(set) var surveys: [WiFiSurvey] = []

    private let fileURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("wifi-surveys.json")
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([WiFiSurvey].self, from: data) {
            surveys = stored
        }
    }

    func survey(id: UUID) -> WiFiSurvey? {
        surveys.first { $0.id == id }
    }

    @discardableResult
    func createSurvey(named name: String) -> WiFiSurvey {
        let survey = WiFiSurvey(name: name)
        surveys.insert(survey, at: 0)
        save()
        return survey
    }

    func update(_ survey: WiFiSurvey) {
        guard let index = surveys.firstIndex(where: { $0.id == survey.id }) else { return }
        surveys[index] = survey
        save()
    }

    func delete(id: UUID) {
        surveys.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(surveys) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Survey List

struct WiFiSurveyListView: View {
    @ObservedObject private var store = WiFiSurveyStore.shared
    @State private var showingNewSurvey = false
    @State private var newSurveyName = ""
    @State private var openedSurvey: UUID?

    private let tint = Color(red: 0.10, green: 0.62, blue: 0.86)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                heroCard

                if store.surveys.isEmpty {
                    AppEmptyState(
                        icon: "house.and.flag",
                        title: "No Surveys Yet",
                        message: "Create a survey, then walk from room to room and run a test in each one."
                    )
                    .appCard(padding: nil)
                } else {
                    AppSection("Surveys") {
                        ForEach(store.surveys) { survey in
                            NavigationLink(value: survey.id) {
                                AppRow(
                                    icon: "house.fill",
                                    tint: tint,
                                    verbatimTitle: survey.name,
                                    subtitle: "\(survey.testedRooms.count) of \(survey.rooms.count) rooms tested"
                                ) {
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
        .navigationTitle("Wi-Fi Survey")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { id in
            WiFiSurveyDetailView(surveyID: id)
        }
        .navigationDestination(item: $openedSurvey) { id in
            WiFiSurveyDetailView(surveyID: id)
        }
        #if DEBUG
        .onAppear {
            // UI review helper: launch with `-debugOpenFirstSurvey YES`.
            if UserDefaults.standard.bool(forKey: "debugOpenFirstSurvey"), openedSurvey == nil {
                openedSurvey = store.surveys.first?.id
            }
        }
        #endif
        .alert("New Survey", isPresented: $showingNewSurvey) {
            TextField("Name, e.g. Home", text: $newSurveyName)
            Button("Cancel", role: .cancel) { newSurveyName = "" }
            Button("Create") {
                let name = newSurveyName.trimmingCharacters(in: .whitespaces)
                let survey = store.createSurvey(named: name.isEmpty ? String(localized: "Home") : name)
                newSurveyName = ""
                openedSurvey = survey.id
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Room-by-Room Survey")
                    .appFont(size: 22, weight: .bold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)
                Text("Find the best and worst Wi-Fi spots in your home by testing each room.")
                    .appFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Button {
                showingNewSurvey = true
            } label: {
                Label("New Survey", systemImage: "plus")
            }
            .buttonStyle(AppPrimaryButtonStyle(variant: .inverted, tint: tint))
        }
        .appHeroCard(tint: tint)
    }
}

// MARK: - Survey Detail

struct WiFiSurveyDetailView: View {
    let surveyID: UUID

    @ObservedObject private var store = WiFiSurveyStore.shared
    @StateObject private var speedTest = SpeedTestManager()
    @State private var testingRoomID: UUID?
    @State private var showingAddRoom = false
    @State private var newRoomName = ""

    private let tint = Color(red: 0.10, green: 0.62, blue: 0.86)

    private var survey: WiFiSurvey? { store.survey(id: surveyID) }

    private var isTesting: Bool {
        switch speedTest.state {
        case .pingTesting, .downloadTesting, .transitionToUpload, .uploadTesting: return true
        default: return false
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if let survey {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    if survey.testedRooms.count >= 2 {
                        summarySection(survey)
                        chartSection(survey)
                    }
                    roomsSection(survey)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .appPageBackground()
        .navigationTitle(Text(verbatim: survey?.name ?? ""))
        .toolReport(store) { [surveyID] in $0.reportText(for: surveyID) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddRoom = true
                } label: {
                    Label("Add Room", systemImage: "plus")
                }
                .disabled(isTesting)
            }
        }
        .alert("Add Room", isPresented: $showingAddRoom) {
            TextField("Room name, e.g. Kitchen", text: $newRoomName)
            Button("Cancel", role: .cancel) { newRoomName = "" }
            Button("Add") { addRoom() }
        }
        .onChange(of: speedTest.state) { _, state in
            guard state == .finished || state == .failed else { return }
            finishTest(state: state)
        }
        .onDisappear { speedTest.cancelTest() }
    }

    // MARK: Sections

    private func summarySection(_ survey: WiFiSurvey) -> some View {
        AppAdaptiveStack(spacing: 12) {
            if let best = survey.bestRoom {
                summaryCard(title: "Best Spot", room: best, color: AppTheme.ping, icon: "hand.thumbsup.fill")
            }
            if let worst = survey.worstRoom {
                summaryCard(title: "Weakest Spot", room: worst, color: AppTheme.danger, icon: "exclamationmark.triangle.fill")
            }
        }
    }

    private func summaryCard(title: LocalizedStringKey, room: SurveyRoom, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .appFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundStyle(color)
                .textCase(.uppercase)
            Text(verbatim: room.name)
                .appFont(size: 18, weight: .bold, design: .rounded)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
            Text(verbatim: "↓ \((room.downloadMbps ?? 0).fixed(1)) Mbps")
                .appFont(size: 14, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(AppTheme.secondaryText)
        }
        .appCard()
        .accessibilityElement(children: .combine)
    }

    private func chartSection(_ survey: WiFiSurvey) -> some View {
        let peak = max(survey.bestRoom?.downloadMbps ?? 1, 1)

        return VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader("Download by Room")

            VStack(alignment: .leading, spacing: 12) {
                ForEach(survey.testedRooms) { room in
                    let mbps = room.downloadMbps ?? 0
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(verbatim: room.name)
                                .appFont(size: 13, weight: .semibold, design: .rounded)
                                .foregroundStyle(AppTheme.primaryText)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(verbatim: "\(mbps.fixed(0)) Mbps")
                                .appFont(size: 12, weight: .semibold, design: .rounded)
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(AppTheme.ink.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(color(for: room, in: survey))
                                        .frame(width: max(proxy.size.width * mbps / peak, 6))
                                }
                        }
                        .frame(height: 8)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: room.name))
                    .accessibilityValue(Text(verbatim: "\(mbps.fixed(0)) Mbps"))
                }
            }
            .appCard()
        }
    }

    private func roomsSection(_ survey: WiFiSurvey) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader("Rooms")

            if survey.rooms.isEmpty {
                VStack(spacing: 14) {
                    AppEmptyState(
                        icon: "door.left.hand.open",
                        title: "Add your first room",
                        message: "Go to the room, add it here and tap Test. Each test takes about 20 seconds."
                    )
                    Button {
                        showingAddRoom = true
                    } label: {
                        Label("Add Room", systemImage: "plus")
                    }
                    .buttonStyle(AppPrimaryButtonStyle(tint: tint))
                    .padding([.horizontal, .bottom], 16)
                }
                .appCard(padding: nil)
            } else {
                VStack(spacing: 0) {
                    ForEach(survey.rooms) { room in
                        roomRow(room, in: survey)
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteRoom(room)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        if room.id != survey.rooms.last?.id {
                            AppRowDivider()
                        }
                    }
                }
                .appCard(padding: nil)
            }
        }
    }

    private func roomRow(_ room: SurveyRoom, in survey: WiFiSurvey) -> some View {
        HStack(spacing: 14) {
            AppIconTile(systemName: "door.left.hand.open", tint: color(for: room, in: survey))

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: room.name)
                    .appFont(size: 16, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)

                if testingRoomID == room.id {
                    Text(verbatim: liveStatus)
                        .appFont(size: 12, weight: .medium, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(tint)
                } else if let down = room.downloadMbps, let up = room.uploadMbps, let ping = room.ping {
                    Text(verbatim: "↓ \(down.fixed(1))  ↑ \(up.fixed(1)) Mbps · \(ping.fixed(0)) ms")
                        .appFont(size: 12, weight: .medium, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    Text("Not tested yet")
                        .appFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }

            Spacer(minLength: 8)

            if testingRoomID == room.id {
                Button("Stop") { speedTest.cancelTest(); testingRoomID = nil }
                    .appFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.danger)
            } else {
                Button(room.download == nil ? "Test" : "Retest") { startTest(in: room) }
                    .appFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundStyle(tint)
                    .disabled(isTesting)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Helpers

    private var liveStatus: String {
        switch speedTest.state {
        case .pingTesting: return String(localized: "Measuring Ping…")
        case .downloadTesting:
            return String(localized: "Download") + " " + (speedTest.displayDownloadSpeed * 8 / 1_000_000).fixed(1) + " Mbps"
        case .transitionToUpload: return String(localized: "Preparing Upload…")
        case .uploadTesting:
            return String(localized: "Upload") + " " + (speedTest.displayUploadSpeed * 8 / 1_000_000).fixed(1) + " Mbps"
        default: return ""
        }
    }

    /// Green for the best room, red for the weakest, neutral otherwise.
    private func color(for room: SurveyRoom, in survey: WiFiSurvey) -> Color {
        guard room.download != nil else { return .gray }
        if room.id == survey.bestRoom?.id { return AppTheme.ping }
        if room.id == survey.worstRoom?.id { return AppTheme.danger }
        return tint
    }

    private func addRoom() {
        let name = newRoomName.trimmingCharacters(in: .whitespaces)
        newRoomName = ""
        guard !name.isEmpty, var survey else { return }
        survey.rooms.append(SurveyRoom(name: name))
        store.update(survey)
    }

    private func deleteRoom(_ room: SurveyRoom) {
        guard var survey else { return }
        survey.rooms.removeAll { $0.id == room.id }
        store.update(survey)
    }

    private func startTest(in room: SurveyRoom) {
        testingRoomID = room.id
        Task { await speedTest.startTest() }
    }

    private func finishTest(state: SpeedTestState) {
        defer { testingRoomID = nil }
        guard state == .finished, let roomID = testingRoomID, var survey,
              let index = survey.rooms.firstIndex(where: { $0.id == roomID }) else { return }
        survey.rooms[index].download = speedTest.finalDownload
        survey.rooms[index].upload = speedTest.finalUpload
        survey.rooms[index].ping = speedTest.ping
        survey.rooms[index].testedAt = Date()
        store.update(survey)
    }
}

#Preview {
    NavigationStack {
        WiFiSurveyListView()
    }
}
