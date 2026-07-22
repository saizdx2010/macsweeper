import Foundation

/// Loads declarative cleanup rules and (later) walks the filesystem.
actor ScanEngine {
    private let rulesURL: URL?

    init(bundle: Bundle = .main) {
        self.rulesURL = bundle.url(forResource: "cleanup-rules", withExtension: "json")
    }

    /// Loads rules from the app bundle. Does not scan disk yet.
    func loadCategories() throws -> [ScanCategory] {
        guard let rulesURL else {
            throw ScanEngineError.rulesNotFound
        }
        let data = try Data(contentsOf: rulesURL)
        let decoder = JSONDecoder()
        return try decoder.decode([ScanCategory].self, from: data)
    }

    /// Scaffold stub — returns empty results. Phase 1 will walk paths.
    func scan() async throws -> [ScanResult] {
        let categories = try loadCategories()
        return categories.map { category in
            ScanResult(
                category: category,
                paths: [],
                isSelected: category.risk.isSelectedByDefault
            )
        }
    }
}

enum ScanEngineError: LocalizedError {
    case rulesNotFound

    var errorDescription: String? {
        switch self {
        case .rulesNotFound:
            return "cleanup-rules.json was not found in the app bundle."
        }
    }
}
