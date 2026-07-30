import AppKit
import Foundation

/// Tappable path segment for the disk browser header.
struct BrowseBreadcrumb: Identifiable, Hashable, Sendable {
    var id: String { path }
    let title: String
    let path: String
}

/// One child entry in the ncdu-style disk browser.
struct DiskBrowseEntry: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let name: String
    let isDirectory: Bool
    /// `nil` while size is still being measured.
    var byteCount: Int64?
    /// Package bundles (`.app`) are opaque — do not drill in.
    let isPackage: Bool

    var canDrillIn: Bool { isDirectory && !isPackage }

    var displayPath: String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

/// Progressive, cancelable one-level disk listing under the user home folder.
@MainActor
final class DiskBrowseService: ObservableObject {
    @Published private(set) var currentPath: String
    @Published private(set) var entries: [DiskBrowseEntry] = []
    @Published private(set) var isMeasuring = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var measuredCount = 0

    private let fileManager: FileManager
    private let homeDirectory: String
    private var measureTask: Task<Void, Never>?
    /// Bumped on each load/cancel so a finishing task cannot clobber a newer one.
    private var measureGeneration = 0
    /// Hard-link + APFS clone dedupe shared across the current directory’s child measurements.
    private var storageDeduper = DiskMeasurement.Deduper()

    init(rootPath: String? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.homeDirectory = (NSHomeDirectory() as NSString).standardizingPath
        let initial = (rootPath ?? NSHomeDirectory() as String)
        self.currentPath = Self.clampToHome(initial, home: homeDirectory)
    }

    var canGoUp: Bool {
        let standardized = URL(fileURLWithPath: currentPath).resolvingSymlinksInPath().path
        let home = URL(fileURLWithPath: homeDirectory).resolvingSymlinksInPath().path
        return standardized != home && standardized.hasPrefix(home + "/")
    }

    var parentPath: String? {
        guard canGoUp else { return nil }
        return (currentPath as NSString).deletingLastPathComponent
    }

    var totalKnownBytes: Int64 {
        entries.compactMap(\.byteCount).reduce(0, +)
    }

    /// Breadcrumb segments from home (`~`) to `currentPath`.
    var breadcrumbs: [BrowseBreadcrumb] {
        let home = URL(fileURLWithPath: homeDirectory).resolvingSymlinksInPath().path
        let current = URL(fileURLWithPath: currentPath).resolvingSymlinksInPath().path
        var crumbs: [BrowseBreadcrumb] = [
            BrowseBreadcrumb(title: "~", path: homeDirectory)
        ]
        guard current != home, current.hasPrefix(home + "/") else {
            return crumbs
        }
        let relative = String(current.dropFirst(home.count + 1))
        var built = homeDirectory
        for component in relative.split(separator: "/") where !component.isEmpty {
            built = (built as NSString).appendingPathComponent(String(component))
            crumbs.append(BrowseBreadcrumb(title: String(component), path: built))
        }
        return crumbs
    }

    func loadDirectory(_ path: String) {
        let clamped = Self.clampToHome(path, home: homeDirectory)
        cancel()
        currentPath = clamped
        entries = []
        errorMessage = nil
        measuredCount = 0
        storageDeduper = DiskMeasurement.Deduper()
        startProgressiveMeasure()
    }

    func goUp() {
        guard let parent = parentPath else { return }
        loadDirectory(parent)
    }

    func drill(into entry: DiskBrowseEntry) {
        guard entry.canDrillIn else { return }
        loadDirectory(entry.path)
    }

    func cancel() {
        measureGeneration += 1
        measureTask?.cancel()
        measureTask = nil
        isMeasuring = false
    }

    /// Opens a folder picker; returns the chosen path if it is under home.
    func chooseFolderInteractively() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Browse"
        panel.message = "Choose a folder inside your home folder to browse."
        panel.directoryURL = URL(fileURLWithPath: currentPath, isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let standardized = Self.resolveUnderHome(url.path, home: homeDirectory)
        guard let standardized else {
            errorMessage = "Browse is limited to folders inside your home folder."
            return nil
        }
        return standardized
    }

    // MARK: - Internals

    private func startProgressiveMeasure() {
        let path = currentPath
        let home = homeDirectory
        let fm = fileManager
        measureGeneration += 1
        let generation = measureGeneration
        isMeasuring = true

        // Heavy filesystem work must leave MainActor or the UI beach-balls and Cancel never runs.
        measureTask = Task {
            defer {
                if generation == measureGeneration {
                    measureTask = nil
                }
            }
            do {
                let listed = try await Self.listImmediateChildren(
                    of: path,
                    homeDirectory: home,
                    fileManager: fm
                )
                guard generation == measureGeneration, !Task.isCancelled else { return }
                entries = listed
                measuredCount = 0

                var localDeduper = storageDeduper
                for index in listed.indices {
                    try Task.checkCancellation()
                    guard generation == measureGeneration else { return }
                    let entry = listed[index]
                    let (bytes, updatedDeduper) = try await Self.measureEntry(
                        entry,
                        fileManager: fm,
                        deduper: localDeduper
                    )
                    localDeduper = updatedDeduper
                    guard generation == measureGeneration, !Task.isCancelled else {
                        if generation == measureGeneration {
                            storageDeduper = localDeduper
                        }
                        return
                    }
                    if index < entries.count, entries[index].path == entry.path {
                        entries[index].byteCount = bytes
                        measuredCount += 1
                    }
                }
                guard generation == measureGeneration else { return }
                storageDeduper = localDeduper

                entries.sort { lhs, rhs in
                    let lb = lhs.byteCount ?? -1
                    let rb = rhs.byteCount ?? -1
                    if lb != rb { return lb > rb }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                isMeasuring = false
            } catch is CancellationError {
                if generation == measureGeneration {
                    isMeasuring = false
                }
            } catch {
                if generation == measureGeneration {
                    errorMessage = error.localizedDescription
                    isMeasuring = false
                }
            }
        }
    }

    /// Lists children off the main actor so directory reads cannot freeze the UI.
    nonisolated private static func listImmediateChildren(
        of directoryPath: String,
        homeDirectory: String,
        fileManager: FileManager
    ) async throws -> [DiskBrowseEntry] {
        try Task.checkCancellation()
        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(DiskMeasurement.sizeKeys),
            options: []
        )

        var result: [DiskBrowseEntry] = []
        for url in contents {
            try Task.checkCancellation()
            guard let standardized = resolveUnderHome(url.path, home: homeDirectory) else {
                continue
            }

            let values = try? url.resourceValues(forKeys: DiskMeasurement.sizeKeys)
            let isDir = values?.isDirectory == true
            let isPackage = values?.isPackage == true
            result.append(
                DiskBrowseEntry(
                    path: standardized,
                    name: url.lastPathComponent,
                    isDirectory: isDir,
                    byteCount: nil,
                    isPackage: isPackage
                )
            )
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Measures one entry off the main actor; returns updated storage dedupe state.
    nonisolated private static func measureEntry(
        _ entry: DiskBrowseEntry,
        fileManager: FileManager,
        deduper: DiskMeasurement.Deduper
    ) async throws -> (Int64, DiskMeasurement.Deduper) {
        var local = deduper
        let url = URL(fileURLWithPath: entry.path, isDirectory: entry.isDirectory)
        let bytes = try DiskMeasurement.measureAllocatedSize(
            at: url,
            fileManager: fileManager,
            deduper: &local
        )
        return (bytes, local)
    }

    private static func clampToHome(_ path: String, home: String) -> String {
        resolveUnderHome(path, home: home) ?? home
    }

    /// Resolves symlinks, then returns the path only if it stays under `home`.
    nonisolated private static func resolveUnderHome(_ path: String, home: String) -> String? {
        let resolvedHome = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved == resolvedHome || resolved.hasPrefix(resolvedHome + "/") {
            return resolved
        }
        return nil
    }
}
