import SwiftUI

/// Circular used-space gauge with free-space content in the center.
struct DiskRingView<Content: View>: View {
    let usedFraction: Double
    var lineWidth: CGFloat = 10
    var size: CGFloat = 168
    @ViewBuilder var content: () -> Content

    private var clampedFraction: Double {
        min(max(usedFraction, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clampedFraction)
                .stroke(
                    Color.accentColor.opacity(0.85),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            content()
                .multilineTextAlignment(.center)
        }
        .frame(width: size, height: size)
        .padding(lineWidth / 2)
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
