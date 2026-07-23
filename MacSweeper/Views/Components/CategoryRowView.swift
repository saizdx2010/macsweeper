import SwiftUI

/// Results-list row: selection control, icon, label + risk, size.
struct CategoryRowView: View {
    @Binding var result: ScanResult
    var showsChevron: Bool = false

    private var isManual: Bool {
        result.category.risk == .manual
    }

    private var isRisky: Bool {
        result.category.risk == .risky
    }

    var body: some View {
        HStack(spacing: 10) {
            selectionControl

            CategoryIcon(category: result.category)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.category.label)
                    .lineLimit(1)
                RiskBadge(risk: result.category.risk)
            }

            Spacer(minLength: 8)

            sizeLabel

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .opacity(isRisky ? 0.72 : 1)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var selectionControl: some View {
        if isManual {
            Image(systemName: "minus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 18, height: 18)
        } else {
            Button {
                result.isSelected.toggle()
            } label: {
                Image(systemName: result.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(result.isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 18, height: 18)
            .accessibilityLabel(result.isSelected ? "Selected" : "Not selected")
            .accessibilityAddTraits(.isButton)
        }
    }

    @ViewBuilder
    private var sizeLabel: some View {
        if isManual, result.totalBytes == 0 {
            Text("Guide")
                .foregroundStyle(.secondary)
        } else {
            Text(ByteCountFormatter.string(fromByteCount: result.totalBytes, countStyle: .file))
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    List {
        CategoryRowView(
            result: .constant(
                ScanResult(
                    category: ScanCategory(
                        id: "user_app_caches",
                        label: "App Caches",
                        paths: ["~/Library/Caches"],
                        risk: .safe,
                        description: "Preview"
                    ),
                    paths: [
                        ScannedPath(path: NSHomeDirectory() + "/Library/Caches", byteCount: 2_100_000_000)
                    ],
                    isSelected: true
                )
            ),
            showsChevron: true
        )
    }
    .frame(width: 420, height: 80)
}
