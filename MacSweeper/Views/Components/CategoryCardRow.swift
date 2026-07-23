import SwiftUI

/// Card-styled category row for results and clean summary.
struct CategoryCardRow: View {
    @Binding var result: ScanResult
    var showsSelection: Bool = true
    var showsChevron: Bool = true
    var onDetails: (() -> Void)? = nil

    private var isManual: Bool { result.category.risk == .manual }
    private var isRisky: Bool { result.category.risk == .risky }

    var body: some View {
        MSCard {
            HStack(spacing: 12) {
                if showsSelection {
                    selectionControl
                }

                iconTile

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.category.label)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    RiskBadge(risk: result.category.risk)
                }

                Spacer(minLength: 8)

                sizeLabel

                if showsChevron {
                    Button {
                        onDetails?()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 20, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Details")
                }
            }
        }
        .opacity(isRisky ? 0.75 : 1)
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MSTheme.accent.opacity(0.12))
                .frame(width: 40, height: 40)
            CategoryIcon(category: result.category, pointSize: 18)
        }
    }

    @ViewBuilder
    private var selectionControl: some View {
        if isManual {
            Image(systemName: "minus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 22)
        } else {
            Button {
                result.setAllPathsSelected(!result.isSelected)
            } label: {
                Image(systemName: result.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(result.isSelected ? MSTheme.accent : Color.secondary.opacity(0.55))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(result.isSelected ? "Selected" : "Not selected")
        }
    }

    @ViewBuilder
    private var sizeLabel: some View {
        if isManual, result.totalBytes == 0 {
            Text("Guide")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        } else if result.selectedBytes != result.totalBytes, result.selectedBytes > 0 {
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteCountFormatter.string(fromByteCount: result.selectedBytes, countStyle: .file))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                Text("of \(ByteCountFormatter.string(fromByteCount: result.totalBytes, countStyle: .file))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        } else {
            Text(ByteCountFormatter.string(fromByteCount: result.totalBytes, countStyle: .file))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
    }
}

/// Read-only summary row for clean confirm.
struct CategorySummaryCard: View {
    let result: ScanResult

    var body: some View {
        MSCard {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(MSTheme.accent.opacity(0.12))
                        .frame(width: 40, height: 40)
                    CategoryIcon(category: result.category, pointSize: 18)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.category.label)
                        .font(.body.weight(.medium))
                    if result.category.action == .emptyTrash {
                        Text("Permanent delete")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer(minLength: 8)

                Text(ByteCountFormatter.string(fromByteCount: result.selectedBytes > 0 ? result.selectedBytes : result.totalBytes, countStyle: .file))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
