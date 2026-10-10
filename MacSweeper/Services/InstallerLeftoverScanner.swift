import Foundation

/// Pure filename heuristics tying a downloaded installer to an installed app
/// (unit-tested without disk I/O). Nothing is mounted or opened.
enum InstallerLeftoverPolicy {
    static let installerExtensions: Set<String> = ["dmg", "pkg", "zip"]

    /// Words that decorate installer names but never identify the app.
    private static let noiseTokens: Set<String> = [
        "installer", "install", "setup", "update", "updater", "mac", "macos", "osx", "darwin",
        "arm64", "aarch64", "arm", "x64", "x86", "x86_64", "amd64", "intel", "universal",
        "apple", "silicon", "dmg", "pkg", "zip", "stable", "release", "latest", "for", "app",
    ]

    struct InstalledApp: Equatable {
        /// Display name without `.app`, e.g. "Google Chrome".
        let name: String
        let bundleID: String?
    }

    enum Confidence: Equatable {
        /// Normalized name equals the installed app's name (or bundle ID segment).
        case confident
        /// Only a prefix relation; listed but never pre-checked.
        case possible
    }

    struct Match: Equatable {
        let appName: String
        let confidence: Confidence
    }

    static func isInstallerFileName(_ fileName: String) -> Bool {
        installerExtensions.contains((fileName as NSString).pathExtension.lowercased())
    }

    /// "Slack-4.36.140-arm64.dmg" → "slack"; "Visual Studio Code_1.2.3 Installer.pkg" → "visualstudiocode".
    static func normalizedName(fromFileName fileName: String) -> String {
        var base = fileName
        if isInstallerFileName(fileName) {
            base = (fileName as NSString).deletingPathExtension
        }
        let separators = CharacterSet(charactersIn: " _-()[]+,")
        let tokens = base.lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
            .filter { !noiseTokens.contains($0) && !isVersionToken($0) }
        return fold(tokens.joined())
    }

    static func isVersionToken(_ token: String) -> Bool {
        var rest = Substring(token)
        if rest.hasPrefix("v") { rest = rest.dropFirst() }
        guard let first = rest.first, first.isNumber else { return false }
        return rest.allSatisfy { $0.isNumber || $0 == "." }
    }

    static func fold(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Best installed-app match for an installer file name. Apple apps and
    /// very short names never match — "Notes.zip" is just a zip.
    static func match(
        fileName: String,
        installedApps: [InstalledApp],
        minimumTokenLength: Int = 4
    ) -> Match? {
        guard isInstallerFileName(fileName) else { return nil }
        let token = normalizedName(fromFileName: fileName)
        guard token.count >= minimumTokenLength else { return nil }

        var best: Match?
        var bestLength = 0
        for app in installedApps {
            if let id = app.bundleID, OrphanedAppPolicy.isAppleBundleID(id) { continue }
            let appToken = fold(app.name)
            guard appToken.count >= minimumTokenLength else { continue }

            var candidate: Match?
            if token == appToken {
                candidate = Match(appName: app.name, confidence: .confident)
            } else if let id = app.bundleID,
                      let last = id.split(separator: ".").last,
                      fold(String(last)) == token {
                candidate = Match(appName: app.name, confidence: .confident)
            } else if appToken.hasPrefix(token) || token.hasPrefix(appToken) {
                candidate = Match(appName: app.name, confidence: .possible)
            }
            guard let candidate else { continue }
            let rank = (candidate.confidence == .confident ? 1_000 : 0) + appToken.count
            if rank > bestLength {
                best = candidate
                bestLength = rank
            }
        }
        return best
    }

    static func detail(forAppNamed name: String) -> String {
        "Installer for \(name) (installed)"
    }
}

/// Finds .dmg / .pkg / .zip files in Downloads (top level + one folder deep)
/// whose app is already installed in `/Applications` or `~/Applications`.
enum InstallerLeftoverScanner {
    static func collectInstalledApps(
        fileManager: FileManager,
        homeDirectory: String
    ) -> [InstallerLeftoverPolicy.InstalledApp] {
        var apps: [InstallerLeftoverPolicy.InstalledApp] = []
        for rootPath in ["/Applications", homeDirectory + "/Applications"] {
            let contents = (try? fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: rootPath, isDirectory: true),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for child in contents where child.lastPathComponent.hasSuffix(".app") {
                let name = String(child.lastPathComponent.dropLast(".app".count))
                guard !name.isEmpty else { continue }
                apps.append(.init(name: name, bundleID: Bundle(url: child)?.bundleIdentifier))
            }
        }
        return apps
    }

    static func measure(
        category: ScanCategory,
        fileManager: FileManager,
        homeDirectory: String,
        installedApps: [InstallerLeftoverPolicy.InstalledApp]? = nil,
        deduper: inout DiskMeasurement.Deduper
    ) throws -> ScanResult? {
        let apps = installedApps ?? collectInstalledApps(fileManager: fileManager, homeDirectory: homeDirectory)
        guard !apps.isEmpty else { return nil }

        let downloads = homeDirectory + "/Downloads"
        var files: [URL] = []
        for child in children(of: downloads, fileManager: fileManager) {
            try Task.checkCancellation()
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            if values?.isDirectory == true {
                // Package-style directories (Foo.app, Foo.pkg) are not folders to dig through.
                guard child.pathExtension.isEmpty else { continue }
                files.append(contentsOf: children(of: child.path, fileManager: fileManager))
            } else {
                files.append(child)
            }
        }

        var scannedPaths: [ScannedPath] = []
        for file in files {
            try Task.checkCancellation()
            guard let match = InstallerLeftoverPolicy.match(fileName: file.lastPathComponent, installedApps: apps),
                  isReportable(file, homeDirectory: homeDirectory)
            else { continue }

            let bytes = try DiskMeasurement.measureAllocatedSize(
                at: file,
                fileManager: fileManager,
                deduper: &deduper
            )
            guard bytes > 0 else { continue }
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            scannedPaths.append(
                ScannedPath(
                    path: file.path,
                    byteCount: bytes,
                    isSelected: match.confidence == .confident,
                    contentModificationDate: values?.contentModificationDate,
                    groupKey: match.appName,
                    groupLabel: InstallerLeftoverPolicy.detail(forAppNamed: match.appName)
                )
            )
        }

        guard !scannedPaths.isEmpty else { return nil }
        return ScanResult(
            category: category,
            paths: scannedPaths.sorted { $0.byteCount > $1.byteCount },
            isSelected: false
        )
    }

    private static func isReportable(_ url: URL, homeDirectory: String) -> Bool {
        guard PathSafetyPolicy.isAllowedToTrash(url.path, homeDirectory: homeDirectory),
              !RunningAppSafety.isProtected(url.path)
        else { return false }
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        return values?.isSymbolicLink != true && values?.isRegularFile == true
    }

    private static func children(of directoryPath: String, fileManager: FileManager) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: directoryPath, isDirectory: true),
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}
