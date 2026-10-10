import SwiftUI

/// Circular gradient gauge with centered content.
struct DiskRingView<Content: View>: View {
    let usedFraction: Double
    var lineWidth: CGFloat = 10
    var size: CGFloat = 168
    var progressColors: [Color] = MSTheme.brandColors
    var trackColor: Color = Color.secondary.opacity(0.16)
    @ViewBuilder var content: () -> Content

    private var clampedFraction: Double {
        min(max(usedFraction, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clampedFraction)
                .stroke(
                    // Stretch the full gradient over the filled arc only.
                    AngularGradient(
                        colors: progressColors,
                        center: .center,
                        startAngle: .zero,
                        endAngle: .degrees(360 * max(clampedFraction, 0.01))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: (progressColors.last ?? MSTheme.accent).opacity(0.2), radius: lineWidth * 0.5)

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

#Preview {
    DiskRingView(usedFraction: 0.58) {
        VStack(spacing: 4) {
            Text("42.1 GB")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("free")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
    .padding()
}
