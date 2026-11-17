//
//  ExperienceTestView.swift
//  rinetworkspeed
//
//  Real-world checks next to the speed test: plays an adaptive (HLS) video
//  stream and reports start-up time, stalls and the quality reached, and
//  measures latency to cloud regions where many game servers run.
//

import SwiftUI
import Combine
import AVKit

// MARK: - Video

nonisolated struct VideoTestResult: Equatable, Sendable {
    /// Seconds from start to the first frame; nil if it never started.
    let startupSeconds: Double?
    let stalls: Int
    /// Highest picture height reached (1080 for 1080p).
    let highestHeight: Int
    /// Average download rate the player measured, Mbps.
    let observedMbps: Double?

    nonisolated enum Verdict: Equatable, Sendable {
        case smooth, someBuffering, poor, failed
    }

    var verdict: Verdict {
        guard let startupSeconds else { return .failed }
        if stalls >= 2 || startupSeconds > 6 || highestHeight < 480 { return .poor }
        if stalls == 1 || startupSeconds > 3 { return .someBuffering }
        return .smooth
    }

    /// "1080p", "720p"…
    var qualityLabel: String? {
        highestHeight > 0 ? "\(highestHeight)p" : nil
    }
}

@MainActor
final class VideoStreamProbe: ObservableObject {
    /// Apple's public HLS example stream (several variants up to 1080p).
    static let streamURL = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8")!
    static let duration: TimeInterval = 20

    @Published private(set) var player: AVPlayer?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var currentHeight = 0

    func run() async -> VideoTestResult {
        let item = AVPlayerItem(url: Self.streamURL)
        item.preferredForwardBufferDuration = 0
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        self.player = player
        defer {
            player.pause()
            self.player = nil
        }

        let start = ProcessInfo.processInfo.systemUptime
        var startup: Double?
        var highest = 0
        player.play()

        while ProcessInfo.processInfo.systemUptime - start < Self.duration, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            elapsed = ProcessInfo.processInfo.systemUptime - start
            if startup == nil, player.timeControlStatus == .playing, item.currentTime().seconds > 0 {
                startup = elapsed
            }
            currentHeight = Int(item.presentationSize.height)
            highest = max(highest, currentHeight)
            if item.status == .failed { break }
        }

        let events = item.accessLog()?.events ?? []
        let observed = events.map(\.observedBitrate).filter { $0 > 0 }
        let stalls = events.reduce(0) { $0 + max(0, $1.numberOfStalls) }
        return VideoTestResult(
            startupSeconds: startup,
            stalls: stalls,
            highestHeight: highest,
            observedMbps: observed.isEmpty ? nil : observed.reduce(0, +) / Double(observed.count) / 1_000_000
        )
    }
}

// MARK: - Gaming

nonisolated struct CloudRegion: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// Host answering on port 443 in that region.
    let host: String

    /// AWS regions near Turkey, Europe and the Gulf; many game servers run in these data centres.
    static let regions: [CloudRegion] = [
        CloudRegion(id: "eu-central-1", name: String(localized: "Frankfurt"), host: "dynamodb.eu-central-1.amazonaws.com"),
        CloudRegion(id: "eu-south-1", name: String(localized: "Milan"), host: "dynamodb.eu-south-1.amazonaws.com"),
        CloudRegion(id: "eu-north-1", name: String(localized: "Stockholm"), host: "dynamodb.eu-north-1.amazonaws.com"),
        CloudRegion(id: "eu-west-1", name: String(localized: "Ireland"), host: "dynamodb.eu-west-1.amazonaws.com"),
        CloudRegion(id: "me-south-1", name: String(localized: "Bahrain"), host: "dynamodb.me-south-1.amazonaws.com"),
        CloudRegion(id: "me-central-1", name: String(localized: "UAE"), host: "dynamodb.me-central-1.amazonaws.com"),
        CloudRegion(id: "us-east-1", name: String(localized: "N. Virginia"), host: "dynamodb.us-east-1.amazonaws.com")
    ]
}

nonisolated enum GamingLatency {
    nonisolated enum Rating: Equatable, Sendable {
        case great, good, playable, poor
    }

    /// For fast-paced games: under 40 ms great, 80 good, 120 playable.
    static func rating(milliseconds: Double) -> Rating {
        switch milliseconds {
        case ..<40: return .great
        case ..<80: return .good
        case ..<120: return .playable
        default: return .poor
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ExperienceTestViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var video: VideoTestResult?
    @Published private(set) var regions: [(region: CloudRegion, milliseconds: Double?)] = []
    let videoProbe = VideoStreamProbe()

    private var task: Task<Void, Never>?

    func start() {
        task?.cancel()
        video = nil
        regions = []
        isRunning = true
        task = Task {
            defer { isRunning = false }
            video = await videoProbe.run()
            guard !Task.isCancelled else { return }

            for region in CloudRegion.regions {
                guard !Task.isCancelled else { return }
                var samples: [Double] = []
                for _ in 0..<5 {
                    let ms = await PingMonitor.tcpConnectTime(host: region.host, port: 443, timeout: 2)
                    if ms >= 0 { samples.append(ms) }
                }
                let median = samples.isEmpty ? nil : samples.sorted()[samples.count / 2]
                regions.append((region, median))
            }
            regions.sort { ($0.milliseconds ?? .infinity) < ($1.milliseconds ?? .infinity) }
        }
    }

    func cancel() {
        task?.cancel()
        isRunning = false
    }
}

// MARK: - View

struct ExperienceTestView: View {
    @StateObject private var vm = ExperienceTestViewModel()
    private let tint = Color(red: 0.84, green: 0.28, blue: 0.74)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                ToolHero(icon: "play.tv.fill", title: "Streaming & Gaming",
                         subtitle: "Plays a test video for 20 seconds and measures latency to game server regions.",
                         tint: tint, isRunning: vm.isRunning, startTitle: "Run Test") {
                    vm.isRunning ? vm.cancel() : vm.start()
                }

                VideoPlayerCard(probe: vm.videoProbe)

                if let video = vm.video {
                    videoSection(video)
                }

                if !vm.regions.isEmpty {
                    AppSection("Game Server Regions", footer: "TCP round trip to Amazon Web Services data centres, where many games host servers. Each game uses its own servers, so treat this as an estimate.") {
                        ForEach(Array(vm.regions.enumerated()), id: \.element.region.id) { index, entry in
                            regionRow(entry.region, entry.milliseconds)
                            if index < vm.regions.count - 1 { AppRowDivider(leadingInset: 16) }
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .appPageBackground()
        .navigationTitle("Streaming & Gaming")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vm.cancel() }
    }

    private func videoSection(_ video: VideoTestResult) -> some View {
        AppSection("Video Streaming", footer: "Apple's public test stream, up to 1080p. The player picks a lower quality when the connection can't keep up, and may also cap it to the size of the preview.") {
            switch video.verdict {
            case .smooth:
                CheckRow(status: .pass, title: Text("Smooth playback"), detail: Text("Started quickly and never paused to buffer."))
            case .someBuffering:
                CheckRow(status: .warning, title: Text("Some buffering"), detail: Text("Video played, but started slowly or paused once."))
            case .poor:
                CheckRow(status: .fail, title: Text("Poor playback"), detail: Text("Long start-up, repeated buffering or low quality."))
            case .failed:
                CheckRow(status: .fail, title: Text("The video didn't start"), detail: Text("The test stream couldn't be loaded."))
            }
            AppRowDivider(leadingInset: 16)
            CheckRow(status: .info, title: Text("Start-up time"), value: video.startupSeconds.map { "\($0.fixed(1)) s" } ?? "—")
            AppRowDivider(leadingInset: 16)
            CheckRow(status: .info, title: Text("Buffering pauses"), value: "\(video.stalls)")
            AppRowDivider(leadingInset: 16)
            CheckRow(status: .info, title: Text("Highest quality"), value: video.qualityLabel ?? "—")
            if let mbps = video.observedMbps {
                AppRowDivider(leadingInset: 16)
                CheckRow(status: .info, title: Text("Video download rate"), value: "\(mbps.fixed(1)) Mbps")
            }
        }
    }

    private func regionRow(_ region: CloudRegion, _ milliseconds: Double?) -> some View {
        guard let milliseconds else {
            return CheckRow(status: .fail, title: Text(verbatim: region.name), detail: Text("No answer"), value: "—")
        }
        let status: CheckStatus
        let label: Text
        switch GamingLatency.rating(milliseconds: milliseconds) {
        case .great: status = .pass; label = Text("Great for fast games")
        case .good: status = .pass; label = Text("Good for most games")
        case .playable: status = .warning; label = Text("Playable, noticeable delay")
        case .poor: status = .fail; label = Text("Too slow for fast games")
        }
        return CheckRow(status: status, title: Text(verbatim: region.name), detail: label, value: "\(milliseconds.fixed(0)) ms")
    }
}

/// Shows the test video while it plays.
private struct VideoPlayerCard: View {
    @ObservedObject var probe: VideoStreamProbe

    var body: some View {
        if let player = probe.player {
            VStack(alignment: .leading, spacing: 8) {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                    .allowsHitTesting(false)
                Text("\(Int(probe.elapsed)) of \(Int(VideoStreamProbe.duration)) s · \(probe.currentHeight > 0 ? "\(probe.currentHeight)p" : "…")")
                    .appFont(size: 12, weight: .medium, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}
