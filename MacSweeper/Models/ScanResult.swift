import Foundation

/// A scanned path contribution within a category.
struct ScannedPath: Identifiable, Hashable {
    var id: String { path }
    /// Absolute filesystem path (home-expanded).
    let path: String
    let byteCount: Int64

    /// Home-relative display form, e.g. `~/Library/Caches/...`.
    var displayPath: String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

/// Result of scanning one category.
struct ScanResult: Identifiable, Hashable {
    var id: String { category.id }
    let category: ScanCategory
    let paths: [ScannedPath]
    var isSelected: Bool

    var totalBytes: Int64 {
        paths.reduce(0) { $0 + $1.byteCount }
    }
}
