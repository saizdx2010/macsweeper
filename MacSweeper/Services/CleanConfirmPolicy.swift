import Foundation

/// Decides when Clean needs an extra system confirmation dialog.
enum CleanConfirmPolicy {
    /// Escalate when selected Moderate items meet or exceed this size (1 GB).
    static let moderateByteThreshold: Int64 = 1_000_000_000

    enum Reason: Equatable, Sendable {
        case emptyTrash
        case risky
        case largeModerate(bytes: Int64)
    }

    /// True when the selection includes Empty Trash, any Risky category, or a large Moderate haul.
    static func requiresConfirmation(results: [ScanResult]) -> Bool {
        confirmationReason(results: results) != nil
    }

    static func confirmationReason(results: [ScanResult]) -> Reason? {
        if results.contains(where: { $0.category.action == .emptyTrash }) {
            return .emptyTrash
        }
        if results.contains(where: { $0.category.risk == .risky }) {
            return .risky
        }
        let moderateBytes = results
            .filter { $0.category.risk == .moderate }
            .reduce(Int64(0)) { $0 + $1.selectedBytes }
        if moderateBytes >= moderateByteThreshold {
            return .largeModerate(bytes: moderateBytes)
        }
        return nil
    }
}
