import SwiftUI
import AppKit

/// Light, airy MacSweeper design tokens.
enum MSTheme {
    /// Calm teal-blue brand accent (not system purple).
    static let accent = Color(red: 0.12, green: 0.55, blue: 0.62)
    /// Warm amber when disk pressure is high (≥85% used).
    static let pressure = Color(red: 0.82, green: 0.48, blue: 0.18)

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

/// Soft radial wash behind hero / theater screens.
struct StageBackground: View {
    var body: some View {
        ZStack {
            MSTheme.canvas
            RadialGradient(
                colors: [
                    MSTheme.accent.opacity(0.12),
                    MSTheme.accent.opacity(0.04),
                    .clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            .blendMode(.normal)
        }
        .ignoresSafeArea()
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
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
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
                    .fill(fillColor)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : (isHovered && isEnabled ? 1.015 : 1))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .shadow(
                color: MSTheme.accent.opacity(isHovered && isEnabled ? 0.28 : 0),
                radius: isHovered && isEnabled ? 10 : 0,
                y: isHovered && isEnabled ? 3 : 0
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

    private var fillColor: Color {
        guard isEnabled else { return MSTheme.accent.opacity(0.35) }
        if configuration.isPressed { return MSTheme.accent.opacity(0.88) }
        if isHovered { return MSTheme.accent.opacity(0.92) }
        return MSTheme.accent
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
