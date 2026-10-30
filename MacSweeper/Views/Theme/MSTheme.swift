import SwiftUI
import AppKit

/// MacSweeper "Focus" design tokens: one teal accent, calm surfaces, category color only on icons.
enum MSTheme {
    /// Teal brand accent for primary actions, selection and the disk ring.
    /// Deep enough for white button text in both appearances (≥ 3:1 at bold 15 pt).
    static let accent = adaptive(
        light: NSColor(red: 0.043, green: 0.541, blue: 0.486, alpha: 1),
        dark: NSColor(red: 0.063, green: 0.588, blue: 0.525, alpha: 1)
    )
    /// Lighter teal for the top of the primary button and the ring's leading edge.
    static let accentLight = adaptive(
        light: NSColor(red: 0.063, green: 0.627, blue: 0.553, alpha: 1),
        dark: NSColor(red: 0.110, green: 0.690, blue: 0.608, alpha: 1)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    /// Warm amber when disk pressure is high (≥85% used).
    static let pressure = Color(red: 0.95, green: 0.52, blue: 0.16)
    /// Amber and red text colors, tuned for ≥ 4.5:1 on the window background in each appearance.
    static let warning = adaptive(
        light: NSColor(red: 0.66, green: 0.37, blue: 0.0, alpha: 1),
        dark: NSColor(red: 0.96, green: 0.65, blue: 0.24, alpha: 1)
    )
    static let danger = adaptive(
        light: NSColor(red: 0.78, green: 0.15, blue: 0.17, alpha: 1),
        dark: NSColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1)
    )

    static let brandColors: [Color] = [accentLight, accent]
    static let pressureColors: [Color] = [pressure, Color(red: 0.93, green: 0.27, blue: 0.33)]

    static var brandGradient: LinearGradient {
        LinearGradient(colors: brandColors, startPoint: .top, endPoint: .bottom)
    }

    /// Fallback hues for rules without a custom icon; stable per id.
    static let categoryPalette: [Color] = [
        Color(red: 0.05, green: 0.62, blue: 0.70), // teal
        Color(red: 0.31, green: 0.36, blue: 0.95), // indigo
        Color(red: 0.62, green: 0.33, blue: 0.96), // violet
        Color(red: 0.95, green: 0.36, blue: 0.62), // pink
        Color(red: 0.98, green: 0.55, blue: 0.20), // orange
        Color(red: 0.20, green: 0.70, blue: 0.40), // green
        Color(red: 0.13, green: 0.55, blue: 0.95), // blue
        Color(red: 0.90, green: 0.70, blue: 0.10), // gold
    ]

    /// Stable (non-randomized) hash so a category's color never changes between launches.
    static func color(forCategoryID id: String) -> Color {
        var hash: UInt32 = 5381
        for byte in id.utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        return categoryPalette[Int(hash % UInt32(categoryPalette.count))]
    }

    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let cardFill = Color(nsColor: .controlBackgroundColor)
    static let cardStroke = Color.primary.opacity(0.07)
    static let hairline = Color.primary.opacity(0.08)

    static let pagePadding: CGFloat = 28
    static let cardRadius: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 20
    static let heroRingSize: CGFloat = 210
    static let heroRingLineWidth: CGFloat = 14
    static let ctaWidth: CGFloat = 220

    static let displayFont = Font.system(size: 34, weight: .semibold, design: .rounded)
    static let titleFont = Font.system(size: 22, weight: .semibold, design: .default)
    static let metaFont = Font.caption
}

/// Motion tokens; every animation in the app comes from here.
enum MSMotion {
    /// Hover, press, checkbox.
    static let fast = Animation.easeOut(duration: 0.12)
    /// Navigation, row insert/remove, sheet.
    static let base = Animation.snappy(duration: 0.35)
    /// Ring, meter and count-up.
    static let slow = Animation.smooth(duration: 0.6)
    /// Done check only.
    static let celebrate = Animation.bouncy(duration: 0.5)
    /// Delay between staggered rows; only the first `staggerLimit` rows are staggered.
    static let stagger = 0.06
    static let staggerLimit = 5

    /// `animation`, or a short crossfade when Reduce Motion is on.
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : animation
    }
}

/// Calm static wash behind every screen: a soft light at the top, no motion.
struct StageBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MSTheme.canvas
            RadialGradient(
                colors: [
                    (colorScheme == .dark ? MSTheme.accent.opacity(0.10) : Color.white.opacity(0.9)),
                    .clear,
                ],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Standard card chrome: flat fill, hairline stroke, no shadow.
struct MSCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(MSTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MSTheme.cardFill, in: RoundedRectangle(cornerRadius: MSTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MSTheme.cardRadius, style: .continuous)
                    .stroke(MSTheme.cardStroke, lineWidth: 1)
            )
    }
}

/// Small uppercase group heading ("SAFE TO CLEAN").
struct MSSectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Actionable hover

/// Soft wash + pointing hand for plain text / icon actions.
struct MSActionableButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        MSActionableButtonBody(configuration: configuration, cornerRadius: cornerRadius)
    }
}

private struct MSActionableButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovered || configuration.isPressed ? 0.08 : 0))
                    .padding(-5)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .contentShape(Rectangle())
            .onHover { hovering in
                guard isHovered != hovering else { return }
                isHovered = hovering
                updateCursor(hovering)
            }
            .onDisappear { if isHovered { NSCursor.pop() } }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private func updateCursor(_ hovering: Bool) {
        if hovering {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }
}

extension ButtonStyle where Self == MSActionableButtonStyle {
    static var msActionable: MSActionableButtonStyle { MSActionableButtonStyle() }
}

/// Filled primary CTA with hover lift.
struct MSPrimaryCTAButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        MSPrimaryCTAButtonBody(configuration: configuration, isEnabled: isEnabled)
    }
}

private struct MSPrimaryCTAButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isEnabled: Bool
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                Capsule()
                    .fill(MSTheme.brandGradient)
                    .opacity(fillOpacity)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : (isHovered && isEnabled ? 1.015 : 1))
            .shadow(
                color: MSTheme.accent.opacity(isEnabled ? (isHovered ? 0.45 : 0.28) : 0),
                radius: isHovered ? 12 : 8,
                y: 5
            )
            .contentShape(Capsule())
            .onHover { hovering in
                guard isEnabled else { return }
                guard isHovered != hovering else { return }
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear { if isHovered { NSCursor.pop() } }
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var fillOpacity: Double {
        guard isEnabled else { return 0.35 }
        return configuration.isPressed ? 0.85 : 1
    }
}

/// Secondary CTA with hover wash.
struct MSSecondaryCTAButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        MSSecondaryCTAButtonBody(configuration: configuration, isEnabled: isEnabled)
    }
}

private struct MSSecondaryCTAButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isEnabled: Bool
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(fillOpacity))
            )
            .overlay(
                Capsule()
                    .strokeBorder(MSTheme.cardStroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : (isHovered && isEnabled ? 1.01 : 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.55)
            .contentShape(Capsule())
            .onHover { hovering in
                guard isEnabled else { return }
                guard isHovered != hovering else { return }
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear { if isHovered { NSCursor.pop() } }
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var fillOpacity: Double {
        if configuration.isPressed { return 0.10 }
        if isHovered && isEnabled { return 0.08 }
        return 0.04
    }
}

/// Hover wash + pointing hand for non-Button tappable rows.
struct ActionableHoverModifier: ViewModifier {
    var isEnabled: Bool = true
    var cornerRadius: CGFloat = 10

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovered && isEnabled ? 0.06 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { hovering in
                guard isEnabled else { return }
                guard isHovered != hovering else { return }
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear { if isHovered { NSCursor.pop() } }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

extension View {
    /// Soft hover highlight and pointing-hand cursor for tappable chrome.
    func actionableHover(isEnabled: Bool = true, cornerRadius: CGFloat = 10) -> some View {
        modifier(ActionableHoverModifier(isEnabled: isEnabled, cornerRadius: cornerRadius))
    }
}

/// Button label with an optional leading Sweep Line icon.
struct MSCTALabel: View {
    let title: String
    var icon: MSIcon? = nil
    var expands: Bool = true

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                MSIconView(icon: icon, size: 15)
            }
            Text(title)
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: expands ? .infinity : nil)
        .padding(.horizontal, expands ? 0 : 22)
        .padding(.vertical, 11)
    }
}

/// Large filled brand call-to-action.
struct PrimaryCTAButton: View {
    let title: String
    var icon: MSIcon? = nil
    var isEnabled: Bool = true
    var expands: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MSCTALabel(title: title, icon: icon, expands: expands)
        }
        .buttonStyle(MSPrimaryCTAButtonStyle(isEnabled: isEnabled))
        .disabled(!isEnabled)
    }
}

/// Secondary action matching `PrimaryCTAButton` size and shape.
struct SecondaryCTAButton: View {
    let title: String
    var icon: MSIcon? = nil
    var isEnabled: Bool = true
    var expands: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MSCTALabel(title: title, icon: icon, expands: expands)
        }
        .buttonStyle(MSSecondaryCTAButtonStyle(isEnabled: isEnabled))
        .disabled(!isEnabled)
    }
}

/// NavigationLink-styled primary CTA for route-driven actions.
struct PrimaryCTANavigationLink<Value: Hashable>: View {
    let title: String
    let value: Value
    var icon: MSIcon? = nil
    var isEnabled: Bool = true
    var expands: Bool = true

    var body: some View {
        NavigationLink(value: value) {
            MSCTALabel(title: title, icon: icon, expands: expands)
        }
        .buttonStyle(MSPrimaryCTAButtonStyle(isEnabled: isEnabled))
        .disabled(!isEnabled)
    }
}

/// Byte count that counts up from zero to `value` when `isRevealed` flips inside an animation.
/// The unit is fixed to the final value's unit so the number rolls without unit flicker.
struct CountingBytesText: View, Animatable {
    private var bytes: Double
    private let units: ByteCountFormatter.Units
    private let prefix: String

    init(value: Int64, isRevealed: Bool = true, prefix: String = "") {
        bytes = isRevealed ? Double(value) : 0
        units = Self.units(for: value)
        self.prefix = prefix
    }

    var animatableData: Double {
        get { bytes }
        set { bytes = newValue }
    }

    var body: some View {
        Text(prefix + Self.format(Int64(max(bytes, 0)), units: units))
            .monospacedDigit()
    }

    private static func units(for value: Int64) -> ByteCountFormatter.Units {
        switch abs(value) {
        case 1_000_000_000_000...: return .useTB
        case 1_000_000_000...: return .useGB
        case 1_000_000...: return .useMB
        default: return .useKB
        }
    }

    private static func format(_ bytes: Int64, units: ByteCountFormatter.Units) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = units
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}
