import Foundation

/// Records what was cleaned in the current session.
@MainActor
final class AuditLogService {
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let timestamp: Date
        let categoryID: String
        let path: String
        let byteCount: Int64
        let destination: String
    }

    private(set) var entries: [Entry] = []

    func record(
        categoryID: String,
        path: String,
        byteCount: Int64,
        destination: String = "Trash"
    ) {
        entries.append(
            Entry(
                id: UUID(),
                timestamp: Date(),
                categoryID: categoryID,
                path: path,
                byteCount: byteCount,
                destination: destination
            )
        )
    }

    func clearSession() {
        entries.removeAll()
    }
}
