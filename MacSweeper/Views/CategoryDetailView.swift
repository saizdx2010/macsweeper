import SwiftUI

struct CategoryDetailView: View {
    let result: ScanResult

    var body: some View {
        List {
            Section {
                Text(result.category.description)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Why")
            }

            Section {
                if result.paths.isEmpty {
                    Text("No paths found for this category.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(result.paths) { item in
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
