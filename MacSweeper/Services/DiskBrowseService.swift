import AppKit
import Foundation

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
    /// Hard-link dedupe shared across the current directory’s child measurements.
    private var seenHardLinks = Set<FileIdentity>()

    init(rootPath: String? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.homeDirectory = (NSHomeDirectory() as NSString).standardizingPath
        let initial = (rootPath ?? NSHomeDirectory() as String)
        self.currentPath = Self.clampToHome(initial, home: homeDirectory)
    }

    var canGoUp: Bool {
        let standardized = (currentPath as NSString).standardizingPath
        return standardized != homeDirectory && standardized.hasPrefix(homeDirectory + "/")
    }

    var parentPath: String? {
        guard canGoUp else { return nil }
        return (currentPath as NSString).deletingLastPathComponent
    }

    var totalKnownBytes: Int64 {
        entries.compactMap(\.byteCount).reduce(0, +)
    }

    func loadDirectory(_ path: String) {
        let clamped = Self.clampToHome(path, home: homeDirectory)
        cancel()
        currentPath = clamped
        entries = []
        errorMessage = nil
        measuredCount = 0
        seenHardLinks = []
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

        let standardized = (url.path as NSString).standardizingPath
        guard standardized == homeDirectory || standardized.hasPrefix(homeDirectory + "/") else {
            errorMessage = "Browse is limited to folders inside your home folder."
            return nil
        }
        return standardized
    }

    // MARK: - Internals

    private func startProgressiveMeasure() {
        let path = currentPath
        isMeasuring = true

        measureTask = Task {
            do {
                let listed = try listImmediateChildren(of: path)
                guard !Task.isCancelled else { return }
                entries = listed
                measuredCount = 0

                for index in listed.indices {
                    try Task.checkCancellation()
                    let entry = listed[index]
                    let url = URL(fileURLWithPath: entry.path, isDirectory: entry.isDirectory)
                    let bytes = try DiskMeasurement.measureAllocatedSize(
                        at: url,
                        fileManager: fileManager,
                        seenHardLinks: &seenHardLinks
                    )
                    guard !Task.isCancelled else { return }
                    if index < entries.count, entries[index].path == entry.path {
                        entries[index].byteCount = bytes
                        measuredCount += 1
                    }
                }

                entries.sort { lhs, rhs in
                    let lb = lhs.byteCount ?? -1
                    let rb = rhs.byteCount ?? -1
                    if lb != rb { return lb > rb }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                isMeasuring = false
            } catch is CancellationError {
                isMeasuring = false
            } catch {
                errorMessage = error.localizedDescription
                isMeasuring = false
            }
        }
    }

    private func listImmediateChildren(of directoryPath: String) throws -> [DiskBrowseEntry] {
        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(DiskMeasurement.sizeKeys),
            options: []
        )

        var result: [DiskBrowseEntry] = []
        for url in contents {
            let standardized = (url.path as NSString).standardizingPath
            guard standardized.hasPrefix(homeDirectory + "/") || standardized == homeDirectory else {
                continue
            }
            // Never list outside home via symlink escape.
            if !standardized.hasPrefix(homeDirectory) { continue }

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

    private static func clampToHome(_ path: String, home: String) -> String {
        let standardized = (path as NSString).standardizingPath
        if standardized == home || standardized.hasPrefix(home + "/") {
            return standardized
        }
        return home
    }
}
