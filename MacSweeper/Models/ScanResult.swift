import Foundation

/// A scanned path contribution within a category.
struct ScannedPath: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let byteCount: Int64
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
