import SwiftUI
#if os(macOS)
import AppKit
#endif

struct CategoryDetailView: View {
    let result: ScanResult
    @Binding var path: NavigationPath

    @State private var didCopyCommand = false

    private let maxDisplayedPaths = 100

    private var displayedPaths: [ScannedPath] {
        Array(result.paths.prefix(maxDisplayedPaths))
    }

    private var omittedPathCount: Int {
        max(0, result.paths.count - maxDisplayedPaths)
    }

    /// Categories that expand a folder into per-item rows (Downloads, Trash, etc.).
    private var listsIndividualItems: Bool {
        result.category.scan == .listChildren
            || result.category.action == .emptyTrash
    }

    private var itemsSectionTitle: String {
        listsIndividualItems ? "Items" : "Paths"
    }

    var body: some View {
        ZStack {
            StageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: MSTheme.sectionSpacing) {
                    MSCard {
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(MSTheme.accent.opacity(0.12))
                                    .frame(width: 52, height: 52)
                                CategoryIcon(category: result.category, pointSize: 22)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    RiskBadge(risk: result.category.risk)
                                    Text(result.category.risk.guidanceLine)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text(result.category.description)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let command = result.category.guideCommand {
                        MSCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Command")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text(command)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)

                                Button(didCopyCommand ? "Copied" : "Copy command") {
                                    #if os(macOS)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(command, forType: .string)
                                    #endif
                                    didCopyCommand = true
                                }
                                .disabled(didCopyCommand)

                                Text("MacSweeper does not run this command. Paste it into Terminal yourself.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    MSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(itemsSectionTitle.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            if result.paths.isEmpty {
                                Text(
                                    result.category.guideCommand != nil
                                        ? "No path sizes to list — use the command above."
                                        : "No paths found for this category."
                                )
                                .foregroundStyle(.secondary)
                            } else {
                                ForEach(displayedPaths) { item in
                                    pathRow(for: item)
                                    if item.id != displayedPaths.last?.id {
                                        Divider().opacity(0.4)
                                    }
                                }
                                if omittedPathCount > 0 {
                                    Text("And \(omittedPathCount) more…")
                                        .foregroundStyle(.secondary)
                                }
                                if listsIndividualItems {
                                    Text("\(result.paths.count) items · sizes include folder contents")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                .padding(MSTheme.pagePadding)
            }
        }
        .appDestinationChrome(
            title: result.category.label,
            subtitle: ByteCountFormatter.string(fromByteCount: result.totalBytes, countStyle: .file),
            onBack: { AppNavigation.popLast($path) }
        )
    }

    @ViewBuilder
    private func pathRow(for item: ScannedPath) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if listsIndividualItems {
                Image(systemName: itemIconName(for: item.path))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(item.displayName)
                    .lineLimit(2)
                    .help(item.displayPath)
                    .textSelection(.enabled)
            } else {
                Text(item.displayPath)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            Text(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func itemIconName(for path: String) -> String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return "folder"
        }
        return "doc"
    }
}

#Preview {
    NavigationStack {
        CategoryDetailView(
            result: ScanResult(
                category: ScanCategory(
                    id: "old_downloads",
                    label: "Downloads folder",
                    paths: ["~/Downloads"],
                    risk: .moderate,
                    description: "Everything currently in Downloads. Review carefully — may include keepers.",
                    scan: .listChildren
                ),
                paths: [
                    ScannedPath(
                        path: NSHomeDirectory() + "/Downloads/Installer.dmg",
                        byteCount: 820_000_000
                    )
                ],
                isSelected: true
            ),
            path: .constant(NavigationPath())
        )
    }
}
