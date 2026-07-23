import SwiftUI

/// Compact capsule label for a category's risk level.
struct RiskBadge: View {
    let risk: RiskLevel

    var body: some View {
        Text(risk.displayName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(risk.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(risk.color.opacity(0.12), in: Capsule())
    }
}

#Preview {
    HStack {
        ForEach(RiskLevel.allCases) { risk in
            RiskBadge(risk: risk)
        }
    }
    .padding()
}
