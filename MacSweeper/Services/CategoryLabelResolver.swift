import Foundation

/// Resolves human-readable category labels for history and audit rows.
enum CategoryLabelResolver {
    static func displayLabel(
        categoryID: String,
        storedLabel: String?,
        labelsByID: [String: String]
    ) -> String {
        if let storedLabel, !storedLabel.isEmpty {
            return storedLabel
        }
        if let mapped = labelsByID[categoryID], !mapped.isEmpty {
            return mapped
        }
        return categoryID.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func labelsByID(from categories: [ScanCategory]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.label) })
    }
}
