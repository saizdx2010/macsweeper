import Foundation

/// A scanned path contribution within a category.
struct ScannedPath: Identifiable, Hashable {
    var id: String { path }
    /// Absolute filesystem path (home-expanded).
    let path: String
    let byteCount: Int64
    /// Whether this path is included in the next clean.
    var isSelected: Bool
    /// Content modification date when available (used by Downloads filters).
    let contentModificationDate: Date?

    /// Last path component, e.g. `report.pdf`.
    var displayName: String {
        (path as NSString).lastPathComponent
    }

    /// Home-relative display form, e.g. `~/Library/Caches/...`.
    var displayPath: String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    init(
        path: String,
        byteCount: Int64,
        isSelected: Bool = true,
        contentModificationDate: Date? = nil
    ) {
        self.path = path
        self.byteCount = byteCount
        self.isSelected = isSelected
        self.contentModificationDate = contentModificationDate
    }
}

/// Result of scanning one category.
struct ScanResult: Identifiable, Hashable {
    var id: String { category.id }
    let category: ScanCategory
    var paths: [ScannedPath]
    /// Category-level selection (synced with path selection for non-manual rules).
    var isSelected: Bool

    /// Total discovered size (all paths, selected or not).
    var totalBytes: Int64 {
        paths.reduce(0) { $0 + $1.byteCount }
    }

    /// Size that would be cleaned given current path selection.
    var selectedBytes: Int64 {
        if category.risk == .manual { return 0 }
        if category.action == .emptyTrash {
            return isSelected ? totalBytes : 0
        }
        return paths.filter(\.isSelected).reduce(0) { $0 + $1.byteCount }
    }

    var selectedPathCount: Int {
        if category.action == .emptyTrash {
            return isSelected ? paths.count : 0
        }
        return paths.filter(\.isSelected).count
    }

    /// Whether Detail should show per-item checkboxes.
    var supportsItemSelection: Bool {
        category.risk != .manual && category.action != .emptyTrash && !paths.isEmpty
    }

    /// Toggle every path and the category master flag together.
    mutating func setAllPathsSelected(_ selected: Bool) {
        guard category.risk != .manual else { return }
        isSelected = selected
        for index in paths.indices {
            paths[index].isSelected = selected
        }
    }

    /// Keep category `isSelected` in sync after a path toggle.
    mutating func syncCategorySelectionFromPaths() {
        guard category.risk != .manual else { return }
        if category.action == .emptyTrash { return }
        isSelected = paths.contains(where: \.isSelected)
    }

    /// Copy containing only selected paths (for Clean flow).
    func selectingOnlyCheckedPaths() -> ScanResult? {
        guard category.risk != .manual else { return nil }

        if category.action == .emptyTrash {
            guard isSelected else { return nil }
            return ScanResult(category: category, paths: paths, isSelected: true)
        }

        let checked = paths.filter(\.isSelected)
        guard !checked.isEmpty else { return nil }
        return ScanResult(category: category, paths: checked, isSelected: true)
    }
}
