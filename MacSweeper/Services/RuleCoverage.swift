import Foundation

/// Maps a filesystem path to a cleanup rule that can reclaim it.
struct RuleCoverageMatch: Hashable, Sendable {
    let categoryID: String
    let label: String
    let risk: RiskLevel
}

/// Reverse lookup: path → cleanup rule (from live scan results and/or static rules).
enum RuleCoverage {
    /// Prefer live scan hits; fall back to static rule index.
    static func match(
        path: String,
        scanResults: [ScanResult],
        categories: [ScanCategory],
        homeDirectory: String = NSHomeDirectory()
    ) -> RuleCoverageMatch? {
        let standardized = (path as NSString).standardizingPath

        if let live = matchInScanResults(path: standardized, results: scanResults) {
            return live
        }
        return matchInCategories(path: standardized, categories: categories, homeDirectory: homeDirectory)
    }

    static func matchInScanResults(path: String, results: [ScanResult]) -> RuleCoverageMatch? {
        let standardized = (path as NSString).standardizingPath
        for result in results {
            // Skip pure Manual guides unless the path is listed.
            for scanned in result.paths {
                let scannedPath = (scanned.path as NSString).standardizingPath
                if standardized == scannedPath
                    || standardized.hasPrefix(scannedPath + "/")
                    || scannedPath.hasPrefix(standardized + "/")
                {
                    return RuleCoverageMatch(
                        categoryID: result.category.id,
                        label: result.category.label,
                        risk: result.category.risk
                    )
                }
            }
        }
        return nil
    }

    static func matchInCategories(
        path: String,
        categories: [ScanCategory],
        homeDirectory: String = NSHomeDirectory()
    ) -> RuleCoverageMatch? {
        let standardized = (path as NSString).standardizingPath

        for category in categories {
            if category.action == .emptyTrash { continue }
            if category.risk == .manual { continue }

            switch category.scan {
            case .fixed:
                for rulePath in category.paths {
                    let expanded = expandHome(rulePath, home: homeDirectory)
                    if standardized == expanded
                        || standardized.hasPrefix(expanded + "/")
                        || expanded.hasPrefix(standardized + "/")
                    {
                        return RuleCoverageMatch(
                            categoryID: category.id,
                            label: category.label,
                            risk: category.risk
                        )
                    }
                }

            case .listChildren:
                for rulePath in category.paths {
                    let parent = expandHome(rulePath, home: homeDirectory)
                    if standardized.hasPrefix(parent + "/") {
                        // Immediate child or deeper under a listed parent.
                        return RuleCoverageMatch(
                            categoryID: category.id,
                            label: category.label,
                            risk: category.risk
                        )
                    }
                    if standardized == parent {
                        return RuleCoverageMatch(
                            categoryID: category.id,
                            label: category.label,
                            risk: category.risk
                        )
                    }
                }

            case .findNamedDirs:
                let names = Set(category.findNames ?? [])
                guard !names.isEmpty else { continue }
                let last = (standardized as NSString).lastPathComponent
                guard names.contains(last) else {
                    // Path under a matching named dir?
                    let components = standardized.split(separator: "/").map(String.init)
                    guard components.contains(where: { names.contains($0) }) else { continue }
                    // Ensure under one of the configured roots.
                    let underRoot = category.paths.contains { rulePath in
                        let root = expandHome(rulePath, home: homeDirectory)
                        return standardized == root || standardized.hasPrefix(root + "/")
                    }
                    if underRoot {
                        return RuleCoverageMatch(
                            categoryID: category.id,
                            label: category.label,
                            risk: category.risk
                        )
                    }
                    continue
                }
                let underRoot = category.paths.contains { rulePath in
                    let root = expandHome(rulePath, home: homeDirectory)
                    return standardized == root || standardized.hasPrefix(root + "/")
                }
                if underRoot {
                    return RuleCoverageMatch(
                        categoryID: category.id,
                        label: category.label,
                        risk: category.risk
                    )
                }

            case .unusedApps:
                // Match a top-level .app under any configured Applications root
                // (and anything inside that bundle).
                for rulePath in category.paths {
                    let root = expandHome(rulePath, home: homeDirectory)
                    guard standardized.hasPrefix(root + "/") else { continue }
                    let inner = String(standardized.dropFirst(root.count + 1))
                    let components = inner.split(separator: "/")
                    guard let first = components.first, first.hasSuffix(".app") else { continue }
                    return RuleCoverageMatch(
                        categoryID: category.id,
                        label: category.label,
                        risk: category.risk
                    )
                }
            }
        }
        return nil
    }

    private static func expandHome(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return home + String(path.dropFirst(1))
        }
        return (path as NSString).expandingTildeInPath
    }
}
