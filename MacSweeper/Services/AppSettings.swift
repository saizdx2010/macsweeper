import AppKit
import Foundation
import UniformTypeIdentifiers

/// User preferences: Dev roots and history retention.
@MainActor
final class AppSettings: ObservableObject {
    struct DevRoot: Identifiable, Equatable, Hashable {
        let id: UUID
        let path: String
        let bookmarkData: Data?
    }

    @Published var keepCleanupHistory: Bool {
        didSet { defaults.set(keepCleanupHistory, forKey: Keys.keepHistory) }
    }

    @Published private(set) var customDevRoots: [DevRoot] = []

    private let defaults: UserDefaults

    private enum Keys {
        static let keepHistory = "settings.keepCleanupHistory"
        static let customDevRoots = "settings.customDevRoots"
    }

    /// Built-in roots used when Dev mode is on (same as cleanup-rules.json).
    static let defaultDevRootPaths: [String] = [
        "~/Developer",
        "~/Projects",
        "~/src",
        "~/code",
        "~/Documents/GitHub",
        "~/Desktop",
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Keys.keepHistory) == nil {
            keepCleanupHistory = true
        } else {
            keepCleanupHistory = defaults.bool(forKey: Keys.keepHistory)
        }
        customDevRoots = Self.loadDevRoots(from: defaults)
    }

    /// Absolute paths for discovery walks (default + custom, existing only).
    var resolvedDevScanRoots: [String] {
        var roots: [String] = []
        var seen = Set<String>()

        for tildePath in Self.defaultDevRootPaths {
            let expanded = (tildePath as NSString).expandingTildeInPath
            let standardized = (expanded as NSString).standardizingPath
            guard FileManager.default.fileExists(atPath: standardized) else { continue }
            if seen.insert(standardized).inserted {
                roots.append(standardized)
            }
        }

        for root in customDevRoots {
            guard let url = resolveBookmark(root.bookmarkData, fallbackPath: root.path) else { continue }
            let standardized = (url.path as NSString).standardizingPath
            guard FileManager.default.fileExists(atPath: standardized) else { continue }
            if seen.insert(standardized).inserted {
                roots.append(standardized)
            }
        }

        return roots
    }

    /// Absolute custom roots only (for ScanEngine merge).
    var customDevScanRoots: [String] {
        customDevRoots.compactMap { root in
            guard let url = resolveBookmark(root.bookmarkData, fallbackPath: root.path) else { return nil }
            let standardized = (url.path as NSString).standardizingPath
            guard FileManager.default.fileExists(atPath: standardized) else { return nil }
            return standardized
        }
    }

    func addDevRootInteractively() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Add Folder"
        panel.message = "Choose a folder to scan for Dev caches (node_modules, virtualenvs, build targets)."
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let home = (NSHomeDirectory() as NSString).standardizingPath
        let standardized = (url.path as NSString).standardizingPath
        guard standardized == home || standardized.hasPrefix(home + "/") else {
            presentAlert(
                title: "Folder not allowed",
                message: "Dev scan folders must be inside your home folder."
            )
            return
        }

        if customDevRoots.contains(where: { ($0.path as NSString).standardizingPath == standardized }) {
            return
        }

        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        customDevRoots.append(
            DevRoot(id: UUID(), path: standardized, bookmarkData: bookmark)
        )
        persistDevRoots()
    }

    func removeDevRoot(id: UUID) {
        customDevRoots.removeAll { $0.id == id }
        persistDevRoots()
    }

    // MARK: - Persistence

    private func persistDevRoots() {
        let payload: [[String: Any]] = customDevRoots.map { root in
            var dict: [String: Any] = [
                "id": root.id.uuidString,
                "path": root.path,
            ]
            if let bookmarkData = root.bookmarkData {
                dict["bookmark"] = bookmarkData
            }
            return dict
        }
        defaults.set(payload, forKey: Keys.customDevRoots)
    }

    private static func loadDevRoots(from defaults: UserDefaults) -> [DevRoot] {
        guard let raw = defaults.array(forKey: Keys.customDevRoots) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { dict in
            guard let path = dict["path"] as? String else { return nil }
            let id = (dict["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
            let bookmark = dict["bookmark"] as? Data
            return DevRoot(id: id, path: path, bookmarkData: bookmark)
        }
    }

    private func resolveBookmark(_ data: Data?, fallbackPath: String) -> URL? {
        if let data {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }
        let url = URL(fileURLWithPath: fallbackPath, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
