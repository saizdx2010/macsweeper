import XCTest
@testable import MacSweeper

// MARK: - Pure policy

final class OrphanedAppPolicyTests: XCTestCase {
    func testBundleIDParsingStripsKnownSuffixes() {
        XCTAssertEqual(
            OrphanedAppPolicy.bundleID(fromFileName: "com.tinyspeck.slackmacgap.plist"),
            "com.tinyspeck.slackmacgap"
        )
        XCTAssertEqual(
            OrphanedAppPolicy.bundleID(fromFileName: "com.test.app.savedState"),
            "com.test.app"
        )
        XCTAssertEqual(OrphanedAppPolicy.bundleID(fromFileName: "com.test.app"), "com.test.app")
    }

    func testBundleIDParsingRejectsNonBundleIDNames() {
        XCTAssertNil(OrphanedAppPolicy.bundleID(fromFileName: "Slack"))
        XCTAssertNil(OrphanedAppPolicy.bundleID(fromFileName: "ByHost"))
        XCTAssertNil(OrphanedAppPolicy.bundleID(fromFileName: "zoom.us Backups"))
        XCTAssertNil(OrphanedAppPolicy.bundleID(fromFileName: "com.Upper.Case"))
        XCTAssertNil(OrphanedAppPolicy.bundleID(fromFileName: "nodots"))
        XCTAssertNil(OrphanedAppPolicy.bundleID(fromFileName: "com.double..dot"))
    }

    func testAppleBundleIDsExcluded() {
        XCTAssertTrue(OrphanedAppPolicy.isAppleBundleID("com.apple.Mail"))
        XCTAssertTrue(OrphanedAppPolicy.isAppleBundleID("com.apple"))
        XCTAssertFalse(OrphanedAppPolicy.isAppleBundleID("com.applelike.vendor"))
        XCTAssertFalse(OrphanedAppPolicy.isAppleBundleID("com.tinyspeck.slackmacgap"))
    }

    func testInstalledBundleIDMatch() {
        let installed: Set<String> = ["com.slack.Slack", "us.zoom.xos"]
        XCTAssertTrue(OrphanedAppPolicy.isInstalled(bundleID: "com.slack.Slack", installedBundleIDs: installed))
        XCTAssertFalse(OrphanedAppPolicy.isInstalled(bundleID: "com.slack.slack", installedBundleIDs: installed))
    }

    func testNameMatchesInstalledApp() {
        let installed: Set<String> = ["slack", "google chrome"]
        XCTAssertTrue(OrphanedAppPolicy.nameMatchesInstalledApp("Slack", installedAppNames: installed))
        XCTAssertTrue(OrphanedAppPolicy.nameMatchesInstalledApp("Google", installedAppNames: installed))
        XCTAssertTrue(OrphanedAppPolicy.nameMatchesInstalledApp("Google Chrome Helper", installedAppNames: installed))
        XCTAssertFalse(OrphanedAppPolicy.nameMatchesInstalledApp("Slacker", installedAppNames: installed))
        XCTAssertFalse(OrphanedAppPolicy.nameMatchesInstalledApp("MobileSync", installedAppNames: installed))
    }

    func testCorroboration() {
        let orphans: Set<String> = ["com.tinyspeck.slackmacgap"]
        XCTAssertEqual(
            OrphanedAppPolicy.corroboratingBundleID(name: "Slack", orphanBundleIDs: orphans),
            "com.tinyspeck.slackmacgap"
        )
        XCTAssertNil(OrphanedAppPolicy.corroboratingBundleID(name: "MobileSync", orphanBundleIDs: orphans))
        XCTAssertNil(OrphanedAppPolicy.corroboratingBundleID(name: "Google", orphanBundleIDs: orphans))
        // Tokens shorter than four characters never corroborate.
        XCTAssertNil(OrphanedAppPolicy.corroboratingBundleID(name: "Go", orphanBundleIDs: orphans))
        let zoomOrphans: Set<String> = ["us.zoom.xos"]
        XCTAssertEqual(
            OrphanedAppPolicy.corroboratingBundleID(name: "Zoom", orphanBundleIDs: zoomOrphans),
            "us.zoom.xos"
        )
    }

    func testDisplayNames() {
        XCTAssertEqual(OrphanedAppPolicy.displayName(forBundleID: "com.tinyspeck.slackmacgap"), "Slackmacgap")
        XCTAssertEqual(OrphanedAppPolicy.displayName(forBundleID: "us.zoom.xos"), "Xos")
    }

    func testUserOwnedContainers() {
        let uid = getuid()
        XCTAssertFalse(OrphanedAppPolicy.isUserOwned(ownerAccountID: nil, currentUserID: uid))
        XCTAssertTrue(OrphanedAppPolicy.isUserOwned(ownerAccountID: UInt64(uid), currentUserID: uid))
        XCTAssertFalse(OrphanedAppPolicy.isUserOwned(ownerAccountID: UInt64(uid) + 1, currentUserID: uid))
    }
}

// MARK: - Scanner

final class OrphanedAppLeftoverScannerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSweeperOrphans-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // MARK: Fixtures

    private func libraryURL(_ relative: String) -> URL {
        tempRoot.appendingPathComponent("Library/\(relative)", isDirectory: true)
    }

    private func makeLibraryRoots() throws {
        for root in OrphanedAppLeftoverScanner.LeftoverRoot.allCases {
            try FileManager.default.createDirectory(at: libraryURL(root.rawValue), withIntermediateDirectories: true)
        }
    }

    private func makeInstalledApp(name: String, bundleID: String) throws {
        let appPath = tempRoot
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: appPath.appendingPathComponent("Contents"),
            withIntermediateDirectories: true
        )
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>\(bundleID)</string>
        </dict></plist>
        """
        try plist.write(to: appPath.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
    }

    private func writeFile(_ relative: String, bytes: Int = 2_048) throws -> String {
        let url = tempRoot.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url.path
    }

    private func makeDirectory(_ relative: String, fileCount: Int = 2) throws -> String {
        let dirURL = tempRoot.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        for index in 0..<max(fileCount, 1) {
            try Data(repeating: 0x42, count: 1_024).write(
                to: dirURL.appendingPathComponent("blob\(index).bin")
            )
        }
        return dirURL.path
    }

    private func makeCategory() -> ScanCategory {
        ScanCategory(
            id: "orphaned_app_leftovers",
            label: "Uninstalled app leftovers",
            paths: OrphanedAppLeftoverScanner.LeftoverRoot.allCases.map { "~/" + $0.rawValue },
            risk: .moderate,
            description: "test",
            scan: .orphanedLeftovers
        )
    }

    private func measure(
        installedApps: OrphanedAppLeftoverScanner.InstalledApps,
        fileManager: FileManager = .default
    ) throws -> ScanResult? {
        var deduper = DiskMeasurement.Deduper()
        return try OrphanedAppLeftoverScanner.measure(
            category: makeCategory(),
            fileManager: fileManager,
            homeDirectory: tempRoot.path,
            installedApps: installedApps,
            deduper: &deduper
        )
    }

    private func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    // MARK: Detection

    func testReportsOrphanPathsAndGroupsThemPerApp() throws {
        try makeLibraryRoots()
        try makeInstalledApp(name: "Keeper.app", bundleID: "com.test.keeper")

        let prefs = try writeFile("Library/Preferences/com.orphan.legacy.plist")
        let caches = try makeDirectory("Library/Caches/com.orphan.legacy")
        let support = try makeDirectory("Library/Application Support/LegacyApp")
        let logs = try makeDirectory("Library/Logs/LegacyApp")
        let savedState = try writeFile("Library/Saved Application State/com.orphan.legacy.savedState")
        let container = try makeDirectory("Library/Containers/com.orphan.legacy", fileCount: 1)

        let result = try measure(installedApps: .none)

        let paths = result?.paths.map { resolved($0.path) } ?? []
        let expected = [prefs, caches, support, logs, savedState, container].map(resolved)
        XCTAssertEqual(Set(paths), Set(expected), "every leftover root should contribute exactly one orphan hit")

        // All hits share one group, labeled from the folder-name evidence.
        let groupKeys = Set(result?.paths.compactMap(\.groupKey) ?? [])
        XCTAssertEqual(groupKeys, ["com.orphan.legacy"])
        XCTAssertEqual(result?.paths.first?.groupLabel, "LegacyApp")

        // Moderate risk: nothing pre-selected.
        XCTAssertEqual(result?.isSelected, false)
        XCTAssertEqual(result?.paths.filter(\.isSelected).count, 0)
    }

    func testInstalledAppLeftoversAreNeverReported() throws {
        try makeLibraryRoots()
        try makeInstalledApp(name: "Keeper.app", bundleID: "com.test.keeper")

        _ = try writeFile("Library/Preferences/com.test.keeper.plist")
        _ = try makeDirectory("Library/Caches/com.test.keeper")
        _ = try makeDirectory("Library/Application Support/Keeper")
        _ = try writeFile("Library/Saved Application State/com.test.keeper.savedState")
        _ = try makeDirectory("Library/Containers/com.test.keeper")

        let installed = OrphanedAppLeftoverScanner.InstalledApps(
            bundleIDs: ["com.test.keeper"],
            names: ["keeper"]
        )
        let result = try measure(installedApps: installed)
        XCTAssertNil(result, "installed apps must never appear as orphaned")
    }

    func testAppleAndUnnamedEntriesAreSkipped() throws {
        try makeLibraryRoots()
        _ = try writeFile("Library/Preferences/com.apple.helpd.plist")
        _ = try makeDirectory("Library/Caches/com.apple.Safari")
        _ = try makeDirectory("Library/Caches/MobileSync")
        _ = try makeDirectory("Library/Logs/ByHost")
        _ = try writeFile("Library/Saved Application State/com.apple.Safari.savedState")

        let result = try measure(installedApps: .none)
        XCTAssertNil(result, "Apple data and unattributable folders are never reported")
    }

    func testVendorFolderStaysWhenVendorAppStillInstalled() throws {
        try makeLibraryRoots()
        try makeInstalledApp(name: "Google Chrome.app", bundleID: "com.google.Chrome")

        _ = try makeDirectory("Library/Application Support/Google")
        _ = try writeFile("Library/Preferences/com.orphan.unrelated.plist")

        let installed = OrphanedAppLeftoverScanner.InstalledApps(
            bundleIDs: ["com.google.Chrome"],
            names: ["google chrome"]
        )
        let result = try measure(installedApps: installed)

        let paths = result?.paths.map { resolved($0.path) } ?? []
        XCTAssertEqual(paths.count, 1)
        XCTAssertFalse(
            paths[0].contains("Application Support"),
            "vendor folders backing installed apps are never listed"
        )
    }

    func testUncorroboratedNameFoldersAreNeverReported() throws {
        try makeLibraryRoots()
        _ = try writeFile("Library/Preferences/com.orphan.legacy.plist")
        _ = try makeDirectory("Library/Application Support/MobileSync")

        let result = try measure(installedApps: .none)
        XCTAssertNil(
            result?.paths.first { $0.displayName == "MobileSync" },
            "folders no orphan bundle ID corroborates stay unreported"
        )
        XCTAssertEqual(result?.paths.count, 1)
    }

    // MARK: Safety

    func testProtectedPrefixesAreNeverReported() throws {
        try makeLibraryRoots()
        // Application Support/1Password is a hard-protected trash prefix; the
        // orphan prefs plist next to it is fine and must still be listed.
        _ = try writeFile("Library/Preferences/com.1password.1password.plist")
        _ = try makeDirectory("Library/Application Support/1Password")

        let result = try measure(installedApps: .none)

        let paths = result?.paths.map { resolved($0.path) } ?? []
        XCTAssertEqual(paths.count, 1)
        XCTAssertTrue(paths[0].hasSuffix("Preferences/com.1password.1password.plist"))
        for path in result?.paths.map(\.path) ?? [] {
            XCTAssertTrue(
                PathSafetyPolicy.isAllowedToTrash(path, homeDirectory: tempRoot.path),
                "every reported hit must be accepted by the trash allowlist"
            )
        }
    }

    func testSymlinkedLeftoversAreSkipped() throws {
        try makeLibraryRoots()
        let target = try makeDirectory("Library/Caches/com.orphan.legacy")
        let linkURL = libraryURL("Library/Application Support/LegacyApp")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: URL(fileURLWithPath: target))

        let result = try measure(installedApps: .none)
        XCTAssertNil(
            result?.paths.first { $0.displayName == "LegacyApp" },
            "symlinked entries are never reported"
        )
    }

    func testMissingLibraryYieldsNoResult() throws {
        let result = try measure(installedApps: .none)
        XCTAssertNil(result)
    }

    func testEmptyLeftoverFilesAreSkipped() throws {
        try makeLibraryRoots()
        _ = try writeFile("Library/Preferences/com.orphan.empty.plist", bytes: 0)
        let result = try measure(installedApps: .none)
        XCTAssertNil(result, "zero-byte leftovers carry no reclaimable space")
    }
}

// MARK: - Grouping

final class LeftoverGroupingTests: XCTestCase {
    private func path(_ name: String, bytes: Int64, key: String?, label: String? = nil, selected: Bool = false) -> ScannedPath {
        ScannedPath(path: "/tmp/leftover/\(name)", byteCount: bytes, isSelected: selected, groupKey: key, groupLabel: label)
    }

    func testGroupsByAppWithSizeOrdering() {
        let groups = LeftoverGrouping.groups(from: [
            path("prefs.plist", bytes: 10, key: "com.a.app"),
            path("cache", bytes: 500, key: "com.b.app", label: "BigApp"),
            path("support", bytes: 40, key: "com.a.app", label: "A App"),
            path("cache2", bytes: 300, key: "com.b.app", label: "BigApp"),
        ])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].label, "BigApp")
        XCTAssertEqual(groups[0].totalBytes, 800)
        XCTAssertEqual(groups[1].label, "A App")
        XCTAssertEqual(groups[1].paths.map(\.byteCount), [40, 10])
    }

    func testUnkeyedPathsLandInTrailingOtherGroup() {
        let groups = LeftoverGrouping.groups(from: [
            path("mystery", bytes: 5, key: nil),
            path("known", bytes: 50, key: "com.a.app", label: "A App"),
        ])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].label, "A App")
        XCTAssertEqual(groups[1].label, "Other items")
        XCTAssertEqual(groups[1].paths.count, 1)
    }

    func testDisplayLimitSplitsWholeGroupsAndCountsOmitted() {
        let groups = [
            LeftoverGrouping.Group(key: "big", label: "Big", paths: (0..<5).map { path("b\($0)", bytes: 1, key: "big") }),
            LeftoverGrouping.Group(key: "small", label: "Small", paths: [path("s0", bytes: 1, key: "small")]),
        ]

        let (all, noneOmitted) = LeftoverGrouping.displayGroups(from: groups, limit: 10)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(noneOmitted, 0)

        let (limited, omitted) = LeftoverGrouping.displayGroups(from: groups, limit: 3)
        XCTAssertEqual(limited.count, 1)
        XCTAssertEqual(limited[0].paths.count, 3)
        XCTAssertEqual(omitted, 3, "5 big rows − 3 shown + 1 small group hidden = 3 omitted")
    }
}

// MARK: - Bundled rule

final class OrphanedLeftoversRuleTests: XCTestCase {
    /// The bundled rule must stay conservative: moderate risk (unchecked),
    /// orphan scan strategy, exactly the six user-owned Library roots.
    func testBundledOrphanRuleShape() throws {
        let rulesURL = Bundle(for: ScanEngine.self).url(forResource: "cleanup-rules", withExtension: "json")
        let data = try Data(contentsOf: try XCTUnwrap(rulesURL, "cleanup-rules.json missing from app bundle"))
        let categories = try JSONDecoder().decode([ScanCategory].self, from: data)

        let rule = try XCTUnwrap(
            categories.first { $0.id == "orphaned_app_leftovers" },
            "orphaned_app_leftovers rule missing from bundled rules"
        )
        XCTAssertEqual(rule.scan, .orphanedLeftovers)
        XCTAssertEqual(rule.risk, .moderate)
        XCTAssertFalse(rule.isDevGroup)
        XCTAssertEqual(rule.paths, [
            "~/Library/Preferences",
            "~/Library/Application Support",
            "~/Library/Caches",
            "~/Library/Logs",
            "~/Library/Saved Application State",
            "~/Library/Containers",
        ])
    }

    func testOrphanStrategyDecodesFromJSON() throws {
        let json = #"""
        {"id":"x","label":"X","paths":["~/Library/Caches"],"risk":"moderate","description":"d","scan":"orphaned_leftovers"}
        """#
        let category = try JSONDecoder().decode(ScanCategory.self, from: Data(json.utf8))
        XCTAssertEqual(category.scan, .orphanedLeftovers)
    }
}
