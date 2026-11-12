//
//  DesignSystem.swift
//  rinetworkspeed
//
//  Shared visual language for every screen. Based on the Network Tools redesign:
//  near-black background, grouped translucent cards with hairline borders,
//  uppercase section headers, solid icon tiles and a solid accent hero card.
//  The UI intentionally uses flat colors only (no gradients).
//

import SwiftUI
import UIKit

// MARK: - Theme

enum AppTheme {
    /// Foreground "ink": white in dark mode, near-black in light mode. Use it
    /// (with opacity) for text, icons and subtle fills on neutral surfaces.
    /// On colored surfaces (hero cards, filled buttons, icon tiles) use plain
    /// `.white`, or force the dark color scheme as `appHeroCard` does.
    static let ink = adaptive(dark: .white, light: UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1))

    /// Page background used behind every screen.
    static let background = adaptive(
        dark: UIColor(red: 10 / 255, green: 10 / 255, blue: 10 / 255, alpha: 1),
        light: UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
    )
    /// Fill for grouped cards and list rows.
    static let cardFill = adaptive(dark: UIColor.white.withAlphaComponent(0.05), light: .white)
    /// Hairline border around cards.
    static let cardStroke = ink.opacity(0.08)
    /// Separator between rows inside a card.
    static let separator = ink.opacity(0.08)

    static let primaryText = ink
    static let secondaryText = ink.opacity(0.55)
    static let tertiaryText = ink.opacity(0.4)

    private static func adaptive(dark: UIColor, light: UIColor) -> Color {
        Color(UIColor { traits in traits.userInterfaceStyle == .light ? light : dark })
    }

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

    /// Wraps content in a solid-color hero card used for the most important item on a page.
    func appHeroCard(tint: Color = AppTheme.accent) -> some View {
        self
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
            .shadow(color: tint.opacity(0.35), radius: 16, x: 0, y: 8)
            // Content sits on a saturated color in both themes, so theme
            // tokens inside it must resolve to their light-on-dark values.
            .environment(\.colorScheme, .dark)
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
                    .appFont(size: 12, weight: .regular, design: .rounded)
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
            .appFont(size: 13, weight: .semibold, design: .rounded)
            .foregroundStyle(AppTheme.ink.opacity(0.5))
            .textCase(.uppercase)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
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

/// Rounded solid-color square holding an SF Symbol.
struct AppIconTile: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            // Tiles have a fixed frame, so their glyph must not grow with Dynamic Type.
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.275, style: .continuous))
            // Decorative: the row title next to it already says what it is.
            .accessibilityHidden(true)
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
                    .appFont(size: 16, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .appFont(size: 12, weight: .regular, design: .rounded)
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
            .appFont(size: 13, weight: .semibold)
            .foregroundStyle(AppTheme.ink.opacity(0.3))
            .accessibilityHidden(true)
    }
}

// MARK: - Metric

/// Compact value + unit metric, used in hero cards and stat rows.
struct AppMetric: View {
    let icon: String?
    let value: String
    let unit: String
    var tint: Color = AppTheme.ink
    var caption: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 4) {
            if let caption {
                Text(caption)
                    .appFont(size: 11, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppTheme.secondaryText)
                    .textCase(.uppercase)
            }
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .appFont(size: 11, weight: .bold)
                        .foregroundStyle(tint)
                }
                Text(value)
                    .appFont(size: 17, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.ink)
                    .contentTransition(.numericText())
            }
            Text(unit)
                .appFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Thin vertical divider between `AppMetric`s.
struct AppMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.ink.opacity(0.18))
            .frame(width: 1, height: 28)
    }
}

// MARK: - Buttons

/// Full-width primary action. Use `.inverted` on top of a hero card, passing
/// the card's tint so the label matches it.
struct AppPrimaryButtonStyle: ButtonStyle {
    enum Variant { case filled, inverted }

    var variant: Variant = .filled
    var tint: Color = AppTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(size: 16, weight: .semibold, design: .rounded)
            .foregroundStyle(variant == .inverted ? tint : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                switch variant {
                case .filled:
                    Capsule().fill(tint)
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
            .appFont(size: 15, weight: .semibold, design: .rounded)
            .foregroundStyle(AppTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(AppTheme.ink.opacity(configuration.isPressed ? 0.14 : 0.08)))
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
            .background(configuration.isPressed ? AppTheme.ink.opacity(0.08) : Color.clear)
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
                .appFont(size: 15, weight: .semibold)
                .foregroundStyle(AppTheme.secondaryText)
            TextField(placeholder, text: $text)
                .appFont(size: 16, weight: .medium, design: .rounded)
                .foregroundStyle(AppTheme.ink)
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
                .appFont(size: 34, weight: .semibold)
                .foregroundStyle(AppTheme.tertiaryText)
            Text(title)
                .appFont(size: 17, weight: .semibold, design: .rounded)
                .foregroundStyle(AppTheme.ink.opacity(0.8))
            if let message {
                Text(message)
                    .appFont(size: 13, weight: .regular, design: .rounded)
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
            .appFont(size: 11, weight: .bold, design: .rounded)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

// MARK: - Dynamic Type

/// System font that keeps the design's point size at the default text size and
/// scales with the user's Dynamic Type setting. Prefer this over
/// `.font(.system(size:))`, which ignores the setting.
private struct AppScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Self.textStyle(for: size))
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }

    /// The text style whose scaling curve best matches a given point size.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 28...: return .largeTitle
        case 22..<28: return .title2
        case 20..<22: return .title3
        case 17..<20: return .body
        case 15..<17: return .subheadline
        case 13..<15: return .footnote
        case 12..<13: return .caption
        default: return .caption2
        }
    }
}

extension View {
    func appFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(AppScaledFont(size: size, weight: weight, design: design))
    }
}

// MARK: - Adaptive Layout

/// Lays its children out side by side, or stacked at accessibility text sizes
/// where side-by-side cards would truncate their titles and values.
struct AppAdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}

// MARK: - Appearance

/// User-selected theme, stored under the "appearance" key.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Nil follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Number Formatting

extension BinaryFloatingPoint {
    /// Locale-aware fixed-precision number without grouping, e.g. "12.5" in
    /// English and "12,5" in Turkish. Use instead of `String(format: "%.1f")`,
    /// which always uses a period.
    nonisolated func fixed(_ fractionDigits: Int) -> String {
        Double(self).formatted(.number.precision(.fractionLength(fractionDigits)).grouping(.never))
    }
}
