import SwiftUI

/// Compact category row for the results sheet: checkbox, icon tile, name, size, chevron.
struct CategoryListRow: View {
    @Binding var result: ScanResult
    /// Change since the previous scan ("+1.2 GB since last scan"), shown instead of the item count.
    var change: String? = nil
    var onDetails: (() -> Void)? = nil

    private var isManual: Bool { result.category.risk == .manual }
    private var isRisky: Bool { result.category.risk == .risky }

    var body: some View {
        HStack(spacing: 12) {
            selectionControl

            if let onDetails {
                Button(action: onDetails) {
                    details
                }
                .buttonStyle(.msActionable)
                .accessibilityLabel("Details for \(result.category.label)")
            } else {
                details
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var details: some View {
        HStack(spacing: 12) {
            CategoryIconTile(category: result.category, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.category.label)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isRisky ? AnyShapeStyle(MSTheme.danger) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            sizeLabel

            if onDetails != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if let change { return change }
        if isManual { return "Guide · copy a command to run yourself" }
        let count = result.paths.count
        var parts = ["\(count) item\(count == 1 ? "" : "s")"]
        if result.category.isDevGroup { parts.append("Dev") }
        if isRisky { parts.append("Risky, check the paths") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var selectionControl: some View {
        if isManual {
            Image(systemName: "minus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 16, height: 16)
                .accessibilityLabel("Guide only, no selection")
        } else {
            MSCheckbox(isOn: result.isSelected) {
                result.setAllPathsSelected(!result.isSelected)
            }
            .accessibilityLabel(result.isSelected ? "Selected \(result.category.label)" : "Not selected \(result.category.label)")
        }
    }

    @ViewBuilder
    private var sizeLabel: some View {
        if isManual, result.totalBytes == 0 {
            Text("Guide")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        } else if result.selectedBytes != result.totalBytes, result.selectedBytes > 0 {
            VStack(alignment: .trailing, spacing: 1) {
                Text(ByteCountFormatter.string(fromByteCount: result.selectedBytes, countStyle: .file))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text("of \(ByteCountFormatter.string(fromByteCount: result.totalBytes, countStyle: .file))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        } else {
            Text(ByteCountFormatter.string(fromByteCount: result.totalBytes, countStyle: .file))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(result.isSelected || isManual ? .primary : .secondary)
        }
    }
}

/// Read-only row for the clean confirm list.
struct CategorySummaryRow: View {
    let result: ScanResult

    var body: some View {
        HStack(spacing: 12) {
            CategoryIconTile(category: result.category, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.category.label)
                    .font(.body.weight(.medium))
                if result.category.action == .emptyTrash {
                    Text("Permanent delete")
                        .font(.caption)
                        .foregroundStyle(MSTheme.warning)
                }
            }

            Spacer(minLength: 8)

            Text(ByteCountFormatter.string(fromByteCount: result.selectedBytes > 0 ? result.selectedBytes : result.totalBytes, countStyle: .file))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Grouped list surface: rows separated by inset hairlines on one soft rounded panel.
struct MSGroupedRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    /// Leading inset of the separators; align with the row's title text.
    var separatorInset: CGFloat = 82
    @ViewBuilder var row: (Int, Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                if offset > 0 {
                    Rectangle()
                        .fill(MSTheme.hairline)
                        .frame(height: 1)
                        .padding(.leading, separatorInset)
                }
                row(offset, item)
            }
        }
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MSTheme.cardStroke, lineWidth: 1)
        )
    }
}

/// Rounded teal checkbox.
struct MSCheckbox: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(MSTheme.accent) : AnyShapeStyle(Color.clear))
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(isOn ? Color.clear : Color.secondary.opacity(0.5), lineWidth: 1.2)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(isOn ? 1 : 0.4)
                    .opacity(isOn ? 1 : 0)
            }
            .frame(width: 16, height: 16)
            .animation(MSMotion.fast, value: isOn)
        }
        .buttonStyle(.msActionable)
    }
}
