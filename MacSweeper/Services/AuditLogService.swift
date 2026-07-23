import Foundation

/// Records what was cleaned in the current session (and optionally on disk).
@MainActor
final class AuditLogService: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let timestamp: Date
        let categoryID: String
        let path: String
        let byteCount: Int64
        let destination: String
    }

    struct SessionSummary: Equatable {
        let date: Date
        let freedBytes: Int64
        let itemCount: Int
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var lastClean: SessionSummary?

    private let defaults: UserDefaults
    private let lastCleanDateKey = "lastClean.date"
    private let lastCleanBytesKey = "lastClean.freedBytes"
    private let lastCleanCountKey = "lastClean.itemCount"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let date = defaults.object(forKey: lastCleanDateKey) as? Date {
            lastClean = SessionSummary(
                date: date,
                freedBytes: Int64(defaults.integer(forKey: lastCleanBytesKey)),
                itemCount: defaults.integer(forKey: lastCleanCountKey)
            )
        }
    }

    func record(moved items: [CleanupService.MovedItem]) {
        let now = Date()
        for item in items {
            entries.append(
                Entry(
                    id: UUID(),
                    timestamp: now,
                    categoryID: item.categoryID,
                    path: item.originalPath,
                    byteCount: item.byteCount,
                    destination: item.trashURL.path
                )
            )
        }
    }

    func finishClean(moved items: [CleanupService.MovedItem]) {
        guard !items.isEmpty else { return }

        record(moved: items)

        let summary = SessionSummary(
            date: Date(),
            freedBytes: items.reduce(0) { $0 + $1.byteCount },
            itemCount: items.count
        )
        lastClean = summary
        defaults.set(summary.date, forKey: lastCleanDateKey)
        defaults.set(Int(summary.freedBytes), forKey: lastCleanBytesKey)
        defaults.set(summary.itemCount, forKey: lastCleanCountKey)
        appendToDiskLog(items: items, summary: summary)
    }

    func clearSession() {
        entries.removeAll()
    }

    // MARK: - Optional on-disk log

    private func appendToDiskLog(items: [CleanupService.MovedItem], summary: SessionSummary) {
        guard let url = logFileURL() else { return }

        let formatter = ISO8601DateFormatter()
        var lines: [String] = [
            "--- \(formatter.string(from: summary.date)) freed \(summary.freedBytes) bytes · \(summary.itemCount) items ---"
        ]
        for item in items {
            lines.append(
                "\(formatter.string(from: summary.date))\t\(item.categoryID)\t\(item.byteCount)\t\(item.originalPath)\t→\t\(item.trashURL.path)"
            )
        }
        lines.append("")

        let data = Data(lines.joined(separator: "\n").utf8)
        if fileManager.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private var fileManager: FileManager { .default }

    private func logFileURL() -> URL? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = support.appendingPathComponent("MacSweeper", isDirectory: true)
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return dir.appendingPathComponent("cleanup.log")
    }
}
