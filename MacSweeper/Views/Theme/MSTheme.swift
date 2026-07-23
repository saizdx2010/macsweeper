import SwiftUI

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
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isEnabled ? MSTheme.accent : MSTheme.accent.opacity(0.35))
        )
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
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MSTheme.cardStroke, lineWidth: 1)
        )
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
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isEnabled ? MSTheme.accent : MSTheme.accent.opacity(0.35))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
