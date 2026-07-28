import Foundation

/// Pure helpers for Detail path search and paging.
enum DetailPathQuery {
    static let pageSize = 200

    static func matchesSearch(_ item: ScannedPath, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return item.displayName.localizedCaseInsensitiveContains(trimmed)
            || item.displayPath.localizedCaseInsensitiveContains(trimmed)
    }

    static func displayedPaths(_ paths: [ScannedPath], limit: Int) -> [ScannedPath] {
        Array(paths.prefix(max(0, limit)))
    }

    static func omittedCount(total: Int, limit: Int) -> Int {
        max(0, total - max(0, limit))
    }
}
