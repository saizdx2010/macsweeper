import XCTest
@testable import MacSweeper

final class DetailAgeFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testOlder14MatchesOnlyBeyond14Days() {
        let thirteenDays = now.addingTimeInterval(-13 * 24 * 60 * 60)
        let fifteenDays = now.addingTimeInterval(-15 * 24 * 60 * 60)
        XCTAssertFalse(DetailAgeFilter.older14.matches(thirteenDays, now: now))
        XCTAssertTrue(DetailAgeFilter.older14.matches(fifteenDays, now: now))
        // Unknown age is never matched — cannot verify the file is stale.
        XCTAssertFalse(DetailAgeFilter.older14.matches(nil, now: now))
    }

    func testWiderFiltersKeepSubsumingNarrowerOnes() {
        let twentyDays = now.addingTimeInterval(-20 * 24 * 60 * 60)
        XCTAssertTrue(DetailAgeFilter.older14.matches(twentyDays, now: now))
        XCTAssertFalse(DetailAgeFilter.older30.matches(twentyDays, now: now))
        XCTAssertFalse(DetailAgeFilter.older90.matches(twentyDays, now: now))
    }

    func testAllCasesExposeLabels() {
        XCTAssertEqual(DetailAgeFilter.allCases.map(\.label), ["Any age", ">14 days", ">30 days", ">90 days"])
    }
}

final class ApplicationsTrashPolicyTests: XCTestCase {
    private let home = "/Users/testuser"
    private var service: CleanupService!

    override func setUp() async throws {
        service = CleanupService(fileManager: .default, homeDirectory: home)
    }

    private func allowed(_ path: String) async -> Bool {
        await service.isAllowedToTrash(path)
    }

    func testAllowsTopLevelApplicationsBundle() async {
        let result = await allowed("/Applications/MyTool.app")
        XCTAssertTrue(result)
    }

    func testDeniesApplicationsFolderItself() async {
        let result = await allowed("/Applications")
        XCTAssertFalse(result)
    }

    func testDeniesNestedApplicationsPaths() async {
        let utilities = await allowed("/Applications/Utilities/Terminal.app")
        let contents = await allowed("/Applications/MyTool.app/Contents/MacOS/MyTool")
        let nested = await allowed("/Applications/Something/Inner.app")
        XCTAssertFalse(utilities)
        XCTAssertFalse(contents)
        XCTAssertFalse(nested)
    }

    func testDeniesNonAppBundleNames() async {
        let plainFile = await allowed("/Applications/notes.txt")
        let zipSuffix = await allowed("/Applications/Installer.app.zip")
        XCTAssertFalse(plainFile)
        XCTAssertFalse(zipSuffix)
    }

    func testDeniesSystemLocations() async {
        let system = await allowed("/System/Applications/Chess.app")
        let tmp = await allowed("/tmp/App.app")
        XCTAssertFalse(system)
        XCTAssertFalse(tmp)
    }

    func testHomeApplicationsRemainsAllowed() async {
        let result = await allowed(home + "/Applications/MyTool.app")
        XCTAssertTrue(result)
    }
}

final class UnusedAppEligibilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testUnknownBundleIDExcluded() {
        XCTAssertTrue(UnusedAppEligibility.isExcludedBundleID(nil))
        XCTAssertTrue(UnusedAppEligibility.isExcludedBundleID(""))
    }

    func testAppleBundleIDsExcluded() {
        XCTAssertTrue(UnusedAppEligibility.isExcludedBundleID("com.apple.Safari"))
        XCTAssertFalse(UnusedAppEligibility.isExcludedBundleID("com.nousresearch.hermes"))
    }

    func testUnusedThresholdMatchesUserRequest() {
        let thirteen = now.addingTimeInterval(-13 * 24 * 60 * 60)
        let fifteen = now.addingTimeInterval(-15 * 24 * 60 * 60)
        XCTAssertFalse(UnusedAppEligibility.isUnused(lastUsed: thirteen, now: now, minAgeDays: 14))
        XCTAssertTrue(UnusedAppEligibility.isUnused(lastUsed: fifteen, now: now, minAgeDays: 14))
        // Unknown last-used date: never suggest deletion.
        XCTAssertFalse(UnusedAppEligibility.isUnused(lastUsed: nil, now: now, minAgeDays: 14))
    }
}

final class UnusedAppScannerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSweeperUnusedApps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeApp(
        name: String,
        bundleID: String?,
        creationDate: Date?
    ) throws -> String {
        let appPath = tempRoot
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: appPath.appendingPathComponent("Contents/MacOS"),
            withIntermediateDirectories: true
        )
        var plist = "<plist version=\"1.0\"><dict>"
        if let bundleID {
            plist += "<key>CFBundleIdentifier</key><string>\(bundleID)</string>"
        }
        plist += "</dict></plist>"
        try ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + plist).write(
            to: appPath.appendingPathComponent("Contents/Info.plist"),
            atomically: true,
            encoding: .utf8
        )
        try Data(repeating: 0x41, count: 2_048).write(
            to: appPath.appendingPathComponent("Contents/MacOS/blob.bin")
        )
        if let creationDate {
            try FileManager.default.setAttributes(
                [.creationDate: creationDate],
                ofItemAtPath: appPath.path
            )
        }
        return appPath.path
    }

    /// Tests only use the home-relative root so they stay hermetic; the absolute
    /// `/Applications` root is exercised by ApplicationsTrashPolicyTests.
    private func makeCategory() -> ScanCategory {
        ScanCategory(
            id: "unused_apps",
            label: "Unused apps",
            paths: ["~/Applications"],
            risk: .moderate,
            description: "test",
            scan: .unusedApps,
            minAgeDays: 14
        )
    }

    /// Temp dirs are outside Spotlight's index, so `lastUsedDate` falls back to
    /// the bundle creation date — the same never-opened-app path real scans use.
    func testListsOnlyOldEnoughThirdPartyApps() throws {
        let now = Date()
        let oldApp = try makeApp(
            name: "OldApp.app",
            bundleID: "com.test.oldapp",
            creationDate: now.addingTimeInterval(-30 * 24 * 60 * 60)
        )
        try makeApp(
            name: "RecentApp.app",
            bundleID: "com.test.recent",
            creationDate: now.addingTimeInterval(-2 * 24 * 60 * 60)
        )
        try makeApp(
            name: "SystemApp.app",
            bundleID: "com.apple.test",
            creationDate: now.addingTimeInterval(-30 * 24 * 60 * 60)
        )
        try makeApp(
            name: "Mystery.app",
            bundleID: nil,
            creationDate: now.addingTimeInterval(-30 * 24 * 60 * 60)
        )
        try makeApp(
            name: "Older.app",
            bundleID: "com.test.running",
            creationDate: now.addingTimeInterval(-30 * 24 * 60 * 60)
        )

        let result = try UnusedAppScanner.measure(
            category: makeCategory(),
            fileManager: .default,
            homeDirectory: tempRoot.path,
            now: now,
            runningBundlePaths: [tempRoot.appendingPathComponent("Applications/Older.app").path],
            lastUsedDateProvider: { UnusedAppScanner.creationFallbackDate(at: $0) }
        )

        // FileManager canonicalizes returned URLs (e.g. /var → /private/var),
        // so compare resolved forms.
        let paths = (result?.paths.map(\.path) ?? [])
            .map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        let expected = URL(fileURLWithPath: oldApp).resolvingSymlinksInPath().path
        XCTAssertEqual(paths, [expected], "only the old, identifiable, not-running app should be listed")
        XCTAssertEqual(result?.isSelected, false, "moderate risk must start unselected")
        XCTAssertNotNil(result?.paths.first?.contentModificationDate)
    }

    func testNestedAndNonAppEntriesAreSkipped() throws {
        let now = Date()
        try makeApp(
            name: "Top.app",
            bundleID: "com.test.top",
            creationDate: now.addingTimeInterval(-30 * 24 * 60 * 60)
        )
        // Not an app bundle name / not a directory / nested too deep.
        let appsDir = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        try Data("x".utf8).write(to: appsDir.appendingPathComponent("Installer.app.zip"))
        try FileManager.default.createDirectory(
            at: appsDir.appendingPathComponent("Some Folder/Inner.app", isDirectory: true),
            withIntermediateDirectories: true
        )

        let result = try UnusedAppScanner.measure(
            category: makeCategory(),
            fileManager: .default,
            homeDirectory: tempRoot.path,
            now: now,
            runningBundlePaths: [],
            lastUsedDateProvider: { UnusedAppScanner.creationFallbackDate(at: $0) }
        )

        XCTAssertEqual(result?.paths.compactMap(\.path).count, 1)
        XCTAssertEqual(result?.paths.first?.displayName, "Top.app")
    }

    func testMissingRootsYieldNoResult() throws {
        let category = ScanCategory(
            id: "unused_apps",
            label: "Unused apps",
            paths: ["~/Applications"],
            risk: .moderate,
            description: "test",
            scan: .unusedApps,
            minAgeDays: 14
        )
        let result = try UnusedAppScanner.measure(
            category: category,
            fileManager: .default,
            homeDirectory: "/Users/definitely-missing-home-\(UUID().uuidString)",
            now: Date(),
            runningBundlePaths: []
        )
        XCTAssertNil(result)
    }
}

final class UnusedAppsRuleTests: XCTestCase {
    func testMinAgeDaysDecodesFromJSON() throws {
        let json = #"""
        {"id":"x","label":"X","paths":["/Applications"],"risk":"moderate","description":"d","scan":"unused_apps","min_age_days":14}
        """#
        let category = try JSONDecoder().decode(ScanCategory.self, from: Data(json.utf8))
        XCTAssertEqual(category.scan, .unusedApps)
        XCTAssertEqual(category.minAgeDays, 14)
    }

    /// The bundled Unused apps rule must stay conservative: moderate risk,
    /// opt-in selection, 14-day threshold, both Applications roots.
    func testBundledUnusedAppsRuleShape() throws {
        let rulesURL = Bundle(for: ScanEngine.self).url(forResource: "cleanup-rules", withExtension: "json")
        let data = try Data(contentsOf: try XCTUnwrap(rulesURL, "cleanup-rules.json missing from app bundle"))
        let categories = try JSONDecoder().decode([ScanCategory].self, from: data)

        let rule = try XCTUnwrap(
            categories.first { $0.id == "unused_apps" },
            "unused_apps rule missing from bundled rules"
        )
        XCTAssertEqual(rule.scan, .unusedApps)
        XCTAssertEqual(rule.risk, .moderate)
        XCTAssertEqual(rule.minAgeDays, 14)
        XCTAssertEqual(rule.paths, ["/Applications", "~/Applications"])
        XCTAssertFalse(rule.isDevGroup)
    }
}

final class UnusedAppsRuleCoverageTests: XCTestCase {
    func testAppUnderApplicationsRootMatchesUnusedAppsRule() {
        let category = ScanCategory(
            id: "unused_apps",
            label: "Unused apps",
            paths: ["/Applications", "~/Applications"],
            risk: .moderate,
            description: "test",
            scan: .unusedApps,
            minAgeDays: 14
        )
        let match = RuleCoverage.matchInCategories(
            path: "/Applications/MyTool.app/Contents/MacOS/MyTool",
            categories: [category],
            homeDirectory: "/Users/testuser"
        )
        XCTAssertEqual(match?.categoryID, "unused_apps")

        let homeMatch = RuleCoverage.matchInCategories(
            path: "/Users/testuser/Applications/Other.app",
            categories: [category],
            homeDirectory: "/Users/testuser"
        )
        XCTAssertEqual(homeMatch?.categoryID, "unused_apps")

        let nonApp = RuleCoverage.matchInCategories(
            path: "/Applications/Utilities/Terminal.app",
            categories: [category],
            homeDirectory: "/Users/testuser"
        )
        XCTAssertNil(nonApp, "second-level paths are never suggested by the Unused apps rule")
    }
}
