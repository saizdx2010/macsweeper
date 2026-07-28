import Foundation

/// Decides when Clean needs an extra system confirmation dialog.
enum CleanConfirmPolicy {
    /// True when the selection includes Empty Trash or any Risky category.
    static func requiresConfirmation(results: [ScanResult]) -> Bool {
        results.contains { result in
            result.category.action == .emptyTrash || result.category.risk == .risky
        }
    }
}
