//
//  DesignSystem.swift
//  rinetworkspeed
//
//  Shared visual language for every screen. Based on the Network Tools redesign:
//  near-black background, grouped translucent cards with hairline borders,
//  uppercase section headers, gradient icon tiles and a gradient hero card.
//

import SwiftUI

// MARK: - Theme

enum AppTheme {
    /// Page background used behind every screen.
    static let background = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    /// Fill for grouped cards and list rows.
    static let cardFill = Color.white.opacity(0.05)
    /// Hairline border around cards.
    static let cardStroke = Color.white.opacity(0.08)
    /// Separator between rows inside a card.
    static let separator = Color.white.opacity(0.08)

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)

    static let cardRadius: CGFloat = 18
    static let heroRadius: CGFloat = 24
    static let pagePadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 28

    // Semantic accents shared across the app.
    static let download = Color(red: 0.16, green: 0.47, blue: 0.96)
    static let upload = Color(red: 0.98, green: 0.55, blue: 0.16)
    static let ping = Color(red: 0.13, green: 0.77, blue: 0.47)
    static let accent = Color(red: 0.42, green: 0.22, blue: 0.93)
    static let warning = Color(red: 0.98, green: 0.75, blue: 0.18)
    static let danger = Color(red: 0.99, green: 0.37, blue: 0.37)

    /// Default gradient for hero cards and primary actions.
    static let heroGradient = [download, accent]
}

// MARK: - Page Background

extension View {
    /// Applies the standard page background, extending under safe areas.
    func appPageBackground() -> some View {
        background(AppTheme.background.ignoresSafeArea())
    }

    /// Wraps content in the standard grouped card (translucent fill + hairline border).
    func appCard(padding: CGFloat? = 16) -> some View {
        self
            .padding(padding ?? 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    /// Wraps content in a gradient hero card used for the most important item on a page.
    func appHeroCard(colors: [Color] = AppTheme.heroGradient) -> some View {
        self
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
            .shadow(color: (colors.first ?? .blue).opacity(0.35), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Section

/// Uppercase header + grouped card, matching the Network Tools sections.
struct AppSection<Content: View>: View {
    let title: LocalizedStringKey?
    var footer: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey? = nil, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                AppSectionHeader(title)
            }

            VStack(spacing: 0) {
                content
            }
            .appCard(padding: nil)

            if let footer {
                Text(footer)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct AppSectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
            .textCase(.uppercase)
            .padding(.leading, 4)
    }
}

/// Inset separator placed between rows inside an `AppSection`.
struct AppRowDivider: View {
    /// Leading inset; 70 aligns with text after a 40pt icon tile.
    var leadingInset: CGFloat = 70

    var body: some View {
        Divider()
            .overlay(AppTheme.separator)
            .padding(.leading, leadingInset)
    }
}

// MARK: - Icon Tile

/// Rounded gradient square holding an SF Symbol.
struct AppIconTile: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [tint, tint.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: size * 0.275, style: .continuous)
            )
    }
}

// MARK: - Row

/// Standard list row: icon tile, title, optional subtitle and trailing accessory.
struct AppRow<Trailing: View>: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder let trailing: Trailing

    init(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 14) {
            AppIconTile(systemName: icon, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Chevron used as trailing accessory for navigable rows.
struct AppChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.3))
    }
}

// MARK: - Metric

/// Compact value + unit metric, used in hero cards and stat rows.
struct AppMetric: View {
    let icon: String?
    let value: String
    let unit: String
    var tint: Color = .white
    var caption: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 4) {
            if let caption {
                Text(caption)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .textCase(.uppercase)
            }
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                }
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            Text(unit)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

/// Thin vertical divider between `AppMetric`s.
struct AppMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.18))
            .frame(width: 1, height: 28)
    }
}

// MARK: - Buttons

/// Full-width primary action. Use `.inverted` on top of a hero gradient.
struct AppPrimaryButtonStyle: ButtonStyle {
    enum Variant { case gradient, inverted }

    var variant: Variant = .gradient
    var colors: [Color] = AppTheme.heroGradient

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(variant == .inverted ? (colors.last ?? .blue) : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                switch variant {
                case .gradient:
                    Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                case .inverted:
                    Capsule().fill(.white)
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

/// Secondary action: translucent capsule.
struct AppSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.14 : 0.08)))
            .overlay(Capsule().stroke(AppTheme.cardStroke, lineWidth: 1))
    }
}

/// Subtle scale on press for cards that act as buttons.
struct AppPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

/// Row highlight on press for rows inside an `AppSection`.
struct AppRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.08) : Color.clear)
    }
}

// MARK: - Input

/// Styled text field container for tool inputs (host, domain, IP…).
struct AppInputField: View {
    let icon: String
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var keyboard: UIKeyboardType = .URL
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
            TextField(placeholder, text: $text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .appCard(padding: nil)
    }
}

// MARK: - Empty State

/// Centered placeholder shown before a tool has results.
struct AppEmptyState: View {
    let icon: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.tertiaryText)
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            if let message {
                Text(message)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
    }
}

// MARK: - Status Pill

/// Small capsule label (e.g. "Open", "Valid", "PRO").
struct AppPill: View {
    let text: LocalizedStringKey
    var tint: Color = AppTheme.accent

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
    }
}
