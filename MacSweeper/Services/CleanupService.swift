import Foundation

/// Moves selected scan results to Trash. Stub for Phase 2.
actor CleanupService {
    struct Outcome: Equatable {
        let freedBytes: Int64
        let itemCount: Int
    }

    /// Scaffold stub — no file operations yet.
    func moveToTrash(_ results: [ScanResult]) async throws -> Outcome {
        let selected = results.filter(\.isSelected)
        let bytes = selected.reduce(Int64(0)) { $0 + $1.totalBytes }
        let count = selected.reduce(0) { $0 + $1.paths.count }
        return Outcome(freedBytes: bytes, itemCount: count)
    }
}
