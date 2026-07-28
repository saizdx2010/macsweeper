import Foundation

/// Records what was cleaned in the current session (and optionally on disk / across launches).
@MainActor
final class AuditLogService: ObservableObject {
    struct Entry: Identifiable, Equatable, Codable, Hashable {
        let id: UUID
        let timestamp: Date
        let categoryID: String
        /// Human label when recorded; older history entries may omit this.
        let categoryLabel: String?
        let path: String
        let byteCount: Int64
        let destination: String

        init(
            id: UUID = UUID(),
            timestamp: Date,
            categoryID: String,
            categoryLabel: String? = nil,
            path: String,
            byteCount: Int64,
            destination: String
        ) {
            self.id = id
            self.timestamp = timestamp
            self.categoryID = categoryID
            self.categoryLabel = categoryLabel
            self.path = path
            self.byteCount = byteCount
            self.destination = destination
        }
    }

    struct SessionSummary: Equatable {
        let date: Date
        let freedBytes: Int64
        let itemCount: Int
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var lastClean: SessionSummary?

    private let defaults: UserDefaults
    private let homeDirectory: String
    private let lastCleanDateKey = "lastClean.date"
    private let lastCleanBytesKey = "lastClean.freedBytes"
    private let lastCleanCountKey = "lastClean.itemCount"
    private let historyKey = "audit.persistedEntries"
    private let maxPersistedEntries = 200

    /// When false, history stays session-only and is not written to disk/UserDefaults.
    var keepHistoryEnabled: Bool = true

    init(defaults: UserDefaults = .standard, homeDirectory: String = NSHomeDirectory()) {
        self.defaults = defaults
        self.homeDirectory = (homeDirectory as NSString).standardizingPath
        if let date = defaults.object(forKey: lastCleanDateKey) as? Date {
            lastClean = SessionSummary(
                date: date,
                freedBytes: Int64(defaults.integer(forKey: lastCleanBytesKey)),
                itemCount: defaults.integer(forKey: lastCleanCountKey)
            )
        }
        entries = Self.loadPersistedEntries(from: defaults)
    }

    func record(moved items: [CleanupService.MovedItem]) {
        let now = Date()
        for item in items {
            entries.insert(
                Entry(
                    id: UUID(),
                    timestamp: now,
                    categoryID: item.categoryID,
                    categoryLabel: item.categoryLabel,
                    path: privacyPath(item.originalPath),
                    byteCount: item.byteCount,
                    destination: privacyPath(item.trashURL.path)
                ),
                at: 0
            )
        }
        if entries.count > maxPersistedEntries {
            entries = Array(entries.prefix(maxPersistedEntries))
        }
        persistEntriesIfNeeded()
    }

    func finishClean(outcome: CleanupService.Outcome) {
        var items = outcome.moved
        let movedBytes = items.reduce(Int64(0)) { $0 + $1.byteCount }
        let emptiedCount = max(0, outcome.itemCount - items.count)
        let emptiedBytes = max(Int64(0), outcome.freedBytes - movedBytes)

        if outcome.emptiedTrash && emptiedCount > 0 {
            let trashPath = homeDirectory + "/.Trash"
            items.append(
                CleanupService.MovedItem(
                    categoryID: "empty_trash",
                    categoryLabel: "Empty Trash",
                    originalPath: trashPath,
                    trashURL: URL(fileURLWithPath: trashPath, isDirectory: true),
                    byteCount: emptiedBytes
                )
            )
        }

        guard !items.isEmpty else { return }

        record(moved: items)

        let summary = SessionSummary(
            date: Date(),
            freedBytes: outcome.freedBytes,
            itemCount: outcome.itemCount
        )
        lastClean = summary
        defaults.set(summary.date, forKey: lastCleanDateKey)
        defaults.set(Int(summary.freedBytes), forKey: lastCleanBytesKey)
        defaults.set(summary.itemCount, forKey: lastCleanCountKey)

        if keepHistoryEnabled {
            appendToDiskLog(items: items, summary: summary)
        }
    }

    func finishClean(moved items: [CleanupService.MovedItem]) {
        finishClean(
            outcome: CleanupService.Outcome(
                freedBytes: items.reduce(0) { $0 + $1.byteCount },
                itemCount: items.count,
                moved: items,
                failures: [],
                emptiedTrash: false
            )
        )
    }

    func clearSession() {
        entries.removeAll()
        defaults.removeObject(forKey: historyKey)
    }

    func applyKeepHistorySetting(_ enabled: Bool) {
        keepHistoryEnabled = enabled
        if enabled {
            persistEntriesIfNeeded()
        } else {
            defaults.removeObject(forKey: historyKey)
            if let url = logFileURL() {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    // MARK: - Persistence

    private func persistEntriesIfNeeded() {
        guard keepHistoryEnabled else { return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: historyKey)
    }

    private static func loadPersistedEntries(from defaults: UserDefaults) -> [Entry] {
        guard let data = defaults.data(forKey: "audit.persistedEntries"),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func appendToDiskLog(items: [CleanupService.MovedItem], summary: SessionSummary) {
        guard let url = logFileURL() else { return }

        let formatter = ISO8601DateFormatter()
        var lines: [String] = [
            "--- \(formatter.string(from: summary.date)) freed \(summary.freedBytes) bytes · \(summary.itemCount) items ---"
        ]
        for item in items {
            lines.append(
                "\(formatter.string(from: summary.date))\t\(item.categoryID)\t\(item.byteCount)\t\(privacyPath(item.originalPath))\t→\t\(privacyPath(item.trashURL.path))"
            )
        }
        lines.append("")

        let data = Data(lines.joined(separator: "\n").utf8)
        if fileManager.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            restrictFilePermissions(at: url)
        } else {
            try? data.write(to: url, options: .atomic)
            restrictFilePermissions(at: url)
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
            restrictDirectoryPermissions(at: dir)
        } catch {
            return nil
        }
        return dir.appendingPathComponent("cleanup.log")
    }

    /// Store `~/…` form so username is not written into history / logs.
    private func privacyPath(_ absolute: String) -> String {
        let standardized = (absolute as NSString).standardizingPath
        if standardized == homeDirectory { return "~" }
        if standardized.hasPrefix(homeDirectory + "/") {
            return "~" + standardized.dropFirst(homeDirectory.count)
        }
        return standardized
    }

    private func restrictDirectoryPermissions(at url: URL) {
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: url.path
        )
    }

    private func restrictFilePermissions(at url: URL) {
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path
        )
    }
}
