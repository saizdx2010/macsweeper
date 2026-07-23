import SwiftUI

/// Tinted SF Symbol for a cleanup category.
struct CategoryIcon: View {
    let category: ScanCategory
    var pointSize: CGFloat = 16

    private var tint: Color {
        switch category.risk {
        case .safe, .manual:
            return MSTheme.accent
        case .moderate, .risky:
            return category.risk.color
        }
    }

    var body: some View {
        Image(systemName: category.sfSymbolName)
            .font(.system(size: pointSize, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: pointSize + 8, height: pointSize + 8)
            .accessibilityHidden(true)
    }
}

#Preview {
    CategoryIcon(
        category: ScanCategory(
            id: "user_app_caches",
            label: "App Caches",
            paths: [],
            risk: .safe,
            description: "Preview"
        )
    )
}
