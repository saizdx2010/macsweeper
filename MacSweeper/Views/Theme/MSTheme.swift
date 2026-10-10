import SwiftUI
import AppKit

/// Colorful but restrained MacSweeper design tokens.
enum MSTheme {
    /// Teal brand accent; anchors the brand gradient.
    static let accent = Color(red: 0.05, green: 0.62, blue: 0.70)
    /// Second and third brand stops (indigo → violet).
    static let accentIndigo = Color(red: 0.31, green: 0.36, blue: 0.95)
    static let accentViolet = Color(red: 0.62, green: 0.33, blue: 0.96)
    /// Warm amber when disk pressure is high (≥85% used).
    static let pressure = Color(red: 0.95, green: 0.52, blue: 0.16)

    static let brandColors: [Color] = [accent, accentIndigo, accentViolet]
    static let pressureColors: [Color] = [pressure, Color(red: 0.93, green: 0.27, blue: 0.33)]

    static var brandGradient: LinearGradient {
        LinearGradient(colors: brandColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Distinct category hues; each category keeps the same color across screens.
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
    static let cardStroke = Color.primary.opacity(0.06)

    static let pagePadding: CGFloat = 28
    static let cardRadius: CGFloat = 16
    static let cardPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 20
    static let heroRingSize: CGFloat = 220
    static let heroRingLineWidth: CGFloat = 14
    /// Smaller ring for Home split layout (Scanning keeps `heroRingSize`).
    static let homeRingSize: CGFloat = 176
    static let homeRingLineWidth: CGFloat = 12

    static let displayFont = Font.system(size: 36, weight: .semibold, design: .rounded)
    static let wordmarkFont = Font.system(size: 28, weight: .bold, design: .rounded)
    static let titleFont = Font.system(size: 22, weight: .semibold, design: .default)
    static let metaFont = Font.caption
}

/// Soft, slowly drifting color wash behind hero / theater screens.
struct StageBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var drift = false

    private var blobOpacity: Double { colorScheme == .dark ? 0.16 : 0.10 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                MSTheme.canvas
                blob(MSTheme.accent, size: w * 0.7)
                    .offset(x: drift ? -w * 0.30 : -w * 0.18, y: drift ? -h * 0.32 : -h * 0.22)
                blob(MSTheme.accentViolet, size: w * 0.6)
                    .offset(x: drift ? w * 0.28 : w * 0.36, y: drift ? -h * 0.18 : -h * 0.30)
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(blobOpacity))
            .frame(width: size, height: size)
            .blur(radius: size * 0.22)
    }
}

/// Text filled with the brand gradient.
struct GradientText: View {
    let text: String
    var font: Font = MSTheme.wordmarkFont

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(MSTheme.brandGradient)
    }
}

/// Standard elevated card chrome.
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
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MSTheme.brandGradient)
                    .opacity(fillOpacity)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : (isHovered && isEnabled ? 1.01 : 1))
            .shadow(
                color: MSTheme.accentIndigo.opacity(isHovered && isEnabled ? 0.25 : 0),
                radius: 8,
                y: 3
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MSTheme.cardStroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : (isHovered && isEnabled ? 1.01 : 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.55)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        if configuration.isPressed { return 0.14 }
        if isHovered && isEnabled { return 0.12 }
        return 0.08
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

/// Large filled brand call-to-action.
struct PrimaryCTAButton: View {
    let title: String
    var isEnabled: Bool = true
    var expands: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: expands ? .infinity : nil)
                .padding(.horizontal, expands ? 0 : 18)
                .padding(.vertical, 12)
        }
        .buttonStyle(MSPrimaryCTAButtonStyle(isEnabled: isEnabled))
        .disabled(!isEnabled)
    }
}

/// Secondary action matching `PrimaryCTAButton` size and radius.
struct SecondaryCTAButton: View {
    let title: String
    var isEnabled: Bool = true
    var expands: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: expands ? .infinity : nil)
                .padding(.horizontal, expands ? 0 : 18)
                .padding(.vertical, 12)
        }
        .buttonStyle(MSSecondaryCTAButtonStyle(isEnabled: isEnabled))
        .disabled(!isEnabled)
    }
}

/// NavigationLink-styled primary CTA for route-driven actions.
struct PrimaryCTANavigationLink<Value: Hashable>: View {
    let title: String
    let value: Value
    var isEnabled: Bool = true

    var body: some View {
        NavigationLink(value: value) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(MSPrimaryCTAButtonStyle(isEnabled: isEnabled))
        .disabled(!isEnabled)
    }
}
