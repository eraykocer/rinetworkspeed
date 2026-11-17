//
//  ToolScaffold.swift
//  rinetworkspeed
//
//  Shared pieces for the newer tools (camera finder, Wi-Fi safety, DNS
//  benchmark, NAT type, streaming and gaming): a hero card with one action
//  and a check row with a pass / warning / fail mark.
//

import SwiftUI

nonisolated enum CheckStatus: Equatable, Sendable {
    case pass
    case warning
    case fail
    case info
}

extension CheckStatus {
    var icon: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pass: return AppTheme.ping
        case .warning: return AppTheme.warning
        case .fail: return AppTheme.danger
        case .info: return AppTheme.secondaryText
        }
    }
}

/// Hero card: icon, title, description and one start / stop button.
struct ToolHero: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let tint: Color
    let isRunning: Bool
    let startTitle: LocalizedStringKey
    var stopTitle: LocalizedStringKey = "Stop"
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon)
                    .appFont(size: 24, weight: .semibold)
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.ink.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .appFont(size: 19, weight: .bold, design: .rounded)
                        .foregroundStyle(AppTheme.ink)
                    Text(subtitle)
                        .appFont(size: 13, weight: .medium, design: .rounded)
                        .foregroundStyle(AppTheme.ink.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: action) {
                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView().tint(tint)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(isRunning ? stopTitle : startTitle)
                }
            }
            .buttonStyle(AppPrimaryButtonStyle(variant: .inverted, tint: tint))
        }
        .appHeroCard(tint: tint)
    }
}

/// One line of a check list: mark, title, optional detail and trailing value.
struct CheckRow: View {
    let status: CheckStatus
    let title: Text
    var detail: Text?
    var value: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.icon)
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(status.color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                title
                    .appFont(size: 15, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)
                if let detail {
                    detail
                        .appFont(size: 13, weight: .regular, design: .rounded)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(verbatim: value)
                    .appFont(size: 14, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.ink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Card with a mark and a short explanation, for results and notes.
struct NoteCard: View {
    let status: CheckStatus
    let title: Text
    let message: Text

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AppIconTile(systemName: status.icon, tint: status == .info ? AppTheme.ink.opacity(0.35) : status.color)
            VStack(alignment: .leading, spacing: 3) {
                title
                    .appFont(size: 16, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)
                message
                    .appFont(size: 13, weight: .regular, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .appCard()
        .accessibilityElement(children: .combine)
    }
}
