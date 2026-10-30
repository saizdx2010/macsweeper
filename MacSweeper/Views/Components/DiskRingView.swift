import SwiftUI

/// Circular gauge with centered content: an inset well, a soft track and a teal arc.
struct DiskRingView<Content: View>: View {
    let usedFraction: Double
    var lineWidth: CGFloat = MSTheme.heroRingLineWidth
    var size: CGFloat = MSTheme.heroRingSize
    var progressColors: [Color] = MSTheme.brandColors
    var trackColor: Color = Color.primary.opacity(0.07)
    @ViewBuilder var content: () -> Content

    private var clampedFraction: Double {
        min(max(usedFraction, 0), 1)
    }

    var body: some View {
        ZStack {
            RingWell(inset: lineWidth)

            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clampedFraction)
                .stroke(
                    // Stretch the gradient over the filled arc only.
                    AngularGradient(
                        colors: progressColors,
                        center: .center,
                        startAngle: .zero,
                        endAngle: .degrees(360 * max(clampedFraction, 0.01))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            content()
                .multilineTextAlignment(.center)
        }
        .frame(width: size, height: size)
        .padding(lineWidth / 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Disk usage")
        .accessibilityValue("\(Int((clampedFraction * 100).rounded())) percent used")
    }
}

/// Scan ring: determinate progress arc plus a radar wedge that sweeps while `isActive`.
struct ScanSweepRing<Content: View>: View {
    let progress: Double
    var isActive: Bool = true
    var lineWidth: CGFloat = MSTheme.heroRingLineWidth
    var size: CGFloat = MSTheme.heroRingSize
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RingWell(inset: lineWidth)

            if isActive && !reduceMotion {
                TimelineView(.animation) { timeline in
                    let seconds = timeline.date.timeIntervalSinceReferenceDate
                    // One revolution every 1.8 s.
                    let angle = (seconds.truncatingRemainder(dividingBy: 1.8) / 1.8) * 360
                    Circle()
                        .inset(by: lineWidth)
                        .fill(
                            AngularGradient(
                                stops: [
                                    .init(color: MSTheme.accent.opacity(0), location: 0),
                                    .init(color: MSTheme.accent.opacity(0.22), location: 0.19),
                                    .init(color: MSTheme.accent.opacity(0), location: 0.2),
                                    .init(color: MSTheme.accent.opacity(0), location: 1),
                                ],
                                center: .center
                            )
                        )
                        .rotationEffect(.degrees(angle - 90 - 70))
                }
                .transition(.opacity)
            }

            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(colors: MSTheme.brandColors, center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            content()
                .multilineTextAlignment(.center)
        }
        .frame(width: size, height: size)
        .padding(lineWidth / 2)
        .animation(MSMotion.base, value: isActive)
    }
}

/// Inset "well" inside a ring so the number sits on a soft recessed disc.
private struct RingWell: View {
    let inset: CGFloat

    var body: some View {
        Circle()
            .inset(by: inset * 0.9)
            .fill(MSTheme.cardFill.opacity(0.7))
            .overlay(
                Circle()
                    .inset(by: inset * 0.9)
                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

/// Success mark: the ring draws, then the check springs in. The only bouncy motion in the app.
struct DoneCheckView: View {
    var symbol: MSIcon = .done
    var isUndo: Bool = false
    var size: CGFloat = 92

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringTrim: CGFloat = 0
    @State private var checkTrim: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(MSTheme.accent.opacity(0.10))
            Circle()
                .trim(from: 0, to: ringTrim)
                .stroke(MSTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if isUndo {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(MSTheme.accent)
                    .opacity(checkTrim)
                    .scaleEffect(0.7 + 0.3 * checkTrim)
            } else {
                CheckShape()
                    .trim(from: 0, to: checkTrim)
                    .stroke(MSTheme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.42, height: size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .onAppear(perform: play)
        .onChange(of: isUndo) { _, _ in play() }
        .accessibilityHidden(true)
    }

    private func play() {
        ringTrim = reduceMotion ? 1 : 0
        checkTrim = reduceMotion ? 1 : 0
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.55)) { ringTrim = 1 }
        withAnimation(MSMotion.celebrate.delay(0.4)) { checkTrim = 1 }
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

#Preview {
    HStack(spacing: 32) {
        DiskRingView(usedFraction: 0.63) {
            VStack(spacing: 4) {
                Text("182 GB")
                    .font(MSTheme.displayFont)
                Text("free of 494 GB")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        ScanSweepRing(progress: 0.4) {
            Text("40%").font(MSTheme.displayFont)
        }
        DoneCheckView()
    }
    .padding(40)
}
