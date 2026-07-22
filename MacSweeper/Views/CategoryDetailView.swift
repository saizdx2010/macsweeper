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
                    Text("No paths measured yet (scaffold).")
                        .foregroundStyle(.secondary)
                    ForEach(result.category.paths, id: \.self) { path in
                        Text(path)
                            .font(.system(.body, design: .monospaced))
                    }
                } else {
                    ForEach(result.paths) { item in
                        HStack {
                            Text(item.path)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))
                                .foregroundStyle(.secondary)
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
                paths: [],
                isSelected: true
            )
        )
    }
}
