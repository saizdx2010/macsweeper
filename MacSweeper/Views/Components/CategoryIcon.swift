import SwiftUI

extension ScanCategory {
    /// Custom icon for this rule, when the Sweep Line set covers it.
    var msIcon: MSIcon? { MSIcon.forCategory(id: id) }

    /// Category tint: shared per icon, else a stable hash color.
    var tint: Color { msIcon?.tint ?? MSTheme.color(forCategoryID: id) }
}

/// Category glyph: custom icon when available, the rule's SF Symbol otherwise.
private struct CategoryGlyph: View {
    let category: ScanCategory
    let size: CGFloat

    var body: some View {
        if let icon = category.msIcon {
            MSIconView(icon: icon, size: size)
        } else {
            Image(systemName: category.sfSymbolName)
                .font(.system(size: size * 0.85, weight: .medium))
                .frame(width: size, height: size)
        }
    }
}

/// Tinted glyph for a cleanup category, colored per category.
struct CategoryIcon: View {
    let category: ScanCategory
    var pointSize: CGFloat = 16

    var body: some View {
        CategoryGlyph(category: category, size: pointSize)
            .foregroundStyle(category.tint)
            .frame(width: pointSize + 8, height: pointSize + 8)
            .accessibilityHidden(true)
    }
}

/// Softly tinted tile with a colored glyph, colored per category.
struct CategoryIconTile: View {
    let category: ScanCategory
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(category.tint.opacity(0.13))
            CategoryGlyph(category: category, size: size * 0.56)
                .foregroundStyle(category.tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        CategoryIconTile(
            category: ScanCategory(
                id: "orphaned_app_leftovers",
                label: "Uninstalled app leftovers",
                paths: [],
                risk: .moderate,
                description: "Preview"
            )
        )
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
    .padding()
}
