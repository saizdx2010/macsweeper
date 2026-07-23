import SwiftUI
#if os(macOS)
import AppKit
#endif

struct CategoryDetailView: View {
    let result: ScanResult

    @State private var didCopyCommand = false

    private let maxDisplayedPaths = 100

    private var displayedPaths: [ScannedPath] {
        Array(result.paths.prefix(maxDisplayedPaths))
    }

    private var omittedPathCount: Int {
        max(0, result.paths.count - maxDisplayedPaths)
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    CategoryIcon(category: result.category, pointSize: 22)

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
                .padding(.vertical, 2)
            } header: {
                Text("Why")
            }

            if let command = result.category.guideCommand {
                Section {
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
                } header: {
                    Text("Command")
                } footer: {
                    Text("MacSweeper does not run this command. Paste it into Terminal yourself.")
                }
            }

            Section {
                if result.paths.isEmpty {
                    Text(
                        result.category.guideCommand != nil
                            ? "No path sizes to list — use the command above."
                            : "No paths found for this category."
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(displayedPaths) { item in
                        HStack(alignment: .top) {
                            Text(item.displayPath)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer(minLength: 12)
                            Text(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if omittedPathCount > 0 {
                        Text("And \(omittedPathCount) more…")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Paths")
            }
        }
        .navigationTitle(result.category.label)
        #if os(macOS)
        .navigationSubtitle(ByteCountFormatter.string(fromByteCount: result.totalBytes, countStyle: .file))
        #endif
    }
}

#Preview {
    NavigationStack {
        CategoryDetailView(
            result: ScanResult(
                category: ScanCategory(
                    id: "browser_chrome_cache",
                    label: "Chrome cache",
                    paths: ["~/Library/Caches/Google/Chrome"],
                    risk: .safe,
                    description: "Temporary files; Chrome rebuilds these automatically."
                ),
                paths: [
                    ScannedPath(
                        path: NSHomeDirectory() + "/Library/Caches/Google/Chrome",
                        byteCount: 980_000_000
                    )
                ],
                isSelected: true
            )
        )
    }
}
