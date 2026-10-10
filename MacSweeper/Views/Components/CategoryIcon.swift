import SwiftUI

/// Tinted SF Symbol for a cleanup category, colored per category.
struct CategoryIcon: View {
    let category: ScanCategory
    var pointSize: CGFloat = 16

    private var tint: Color { MSTheme.color(forCategoryID: category.id) }

    var body: some View {
        Image(systemName: category.sfSymbolName)
            .font(.system(size: pointSize, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: pointSize + 8, height: pointSize + 8)
            .accessibilityHidden(true)
    }
}

/// Softly tinted tile with a colored glyph, colored per category.
struct CategoryIconTile: View {
    let category: ScanCategory
    var size: CGFloat = 40

    private var tint: Color { MSTheme.color(forCategoryID: category.id) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(tint.opacity(0.15))
            Image(systemName: category.sfSymbolName)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
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
