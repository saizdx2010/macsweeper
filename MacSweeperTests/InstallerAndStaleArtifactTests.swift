import XCTest
@testable import MacSweeper

final class InstallerLeftoverPolicyTests: XCTestCase {
    private typealias App = InstallerLeftoverPolicy.InstalledApp
    private let apps = [
        App(name: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
        App(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode"),
        App(name: "zoom.us", bundleID: "us.zoom.xos"),
        App(name: "Notes", bundleID: "com.apple.Notes"),
        App(name: "Firefox", bundleID: "org.mozilla.firefox"),
    ]

    func testNormalizationStripsVersionArchAndInstallerWords() {
        XCTAssertEqual(InstallerLeftoverPolicy.normalizedName(fromFileName: "Slack-4.36.140-arm64.dmg"), "slack")
        XCTAssertEqual(InstallerLeftoverPolicy.normalizedName(fromFileName: "Visual Studio Code_1.2.3 Installer.pkg"), "visualstudiocode")
        XCTAssertEqual(InstallerLeftoverPolicy.normalizedName(fromFileName: "Firefox v120.0 (universal).zip"), "firefox")
    }

    func testConfidentExactMatch() {
        let match = InstallerLeftoverPolicy.match(fileName: "Slack-4.36.140-arm64.dmg", installedApps: apps)
        XCTAssertEqual(match, .init(appName: "Slack", confidence: .confident))
        XCTAssertEqual(
            InstallerLeftoverPolicy.match(fileName: "zoomusInstaller.pkg", installedApps: apps)?.appName, "zoom.us"
        )
        XCTAssertEqual(InstallerLeftoverPolicy.detail(forAppNamed: "Slack"), "Installer for Slack (installed)")
    }

    func testBundleIDSegmentIsConfident() {
        let match = InstallerLeftoverPolicy.match(fileName: "slackmacgap_1.0.dmg", installedApps: apps)
        XCTAssertEqual(match?.confidence, .confident)
    }

    func testPrefixOnlyIsPossibleNotConfident() {
        let match = InstallerLeftoverPolicy.match(fileName: "Visual Studio Code Insiders.zip", installedApps: apps)
        XCTAssertEqual(match?.confidence, .possible)
    }

    func testNonMatchesAndNonInstallers() {
        XCTAssertNil(InstallerLeftoverPolicy.match(fileName: "Photoshop-25.dmg", installedApps: apps))
        XCTAssertNil(InstallerLeftoverPolicy.match(fileName: "Slack.txt", installedApps: apps))
        XCTAssertNil(InstallerLeftoverPolicy.match(fileName: "Slack", installedApps: apps))
    }

    func testAppleAppsNeverMatch() {
        XCTAssertNil(InstallerLeftoverPolicy.match(fileName: "Notes.zip", installedApps: apps))
    }

    func testShortTokensNeverMatch() {
        let short = [App(name: "Art", bundleID: "com.example.art")]
        XCTAssertNil(InstallerLeftoverPolicy.match(fileName: "art-1.0.dmg", installedApps: short))
    }
}

final class StaleProjectPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let names = Set(StaleProjectPolicy.defaultArtifactNames)

    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    func testInactivityThreshold() {
        XCTAssertTrue(StaleProjectPolicy.isStale(lastActivity: daysAgo(91), now: now, minAgeDays: 90))
        XCTAssertFalse(StaleProjectPolicy.isStale(lastActivity: daysAgo(89), now: now, minAgeDays: 90))
        XCTAssertFalse(StaleProjectPolicy.isStale(lastActivity: nil, now: now, minAgeDays: 90))
    }

    func testRecentFileEditKeepsOldGitProjectActive() {
        let activity = StaleProjectPolicy.lastActivity(gitActivity: daysAgo(200), topLevelFileDates: [daysAgo(3)])
        XCTAssertFalse(StaleProjectPolicy.isStale(lastActivity: activity, now: now, minAgeDays: 90))
        XCTAssertNil(StaleProjectPolicy.lastActivity(gitActivity: nil, topLevelFileDates: []))
    }

    func testBuildAndDistNeedParentMarker() {
        XCTAssertFalse(StaleProjectPolicy.isArtifactCandidate(name: "build", parentHasMarker: false, names: names))
        XCTAssertFalse(StaleProjectPolicy.isArtifactCandidate(name: "dist", parentHasMarker: false, names: names))
        XCTAssertTrue(StaleProjectPolicy.isArtifactCandidate(name: "dist", parentHasMarker: true, names: names))
        XCTAssertTrue(StaleProjectPolicy.isArtifactCandidate(name: "__pycache__", parentHasMarker: false, names: names))
        XCTAssertFalse(StaleProjectPolicy.isArtifactCandidate(name: "src", parentHasMarker: true, names: names))
    }

    func testNeverDescendsIntoNodeModulesOrSystemDirs() {
        for name in ["node_modules", "Library", ".git"] {
            XCTAssertTrue(StaleProjectPolicy.isNeverDescended(name))
        }
        XCTAssertFalse(StaleProjectPolicy.isNeverDescended("src"))
    }
}

final class StaleProjectScanIntegrationTests: XCTestCase {
    func testOnlyStaleProjectsWithMarkersAreReported() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("ms-stale-\(UUID().uuidString)").path
        defer { try? fm.removeItem(atPath: home) }
        let root = home + "/Developer"

        func write(_ path: String, age days: Double? = nil) throws {
            try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            fm.createFile(atPath: path, contents: Data(repeating: 1, count: 4096))
            if let days {
                try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-days * 86_400)], ofItemAtPath: path)
            }
        }

        try write(root + "/old/package.json", age: 200)
        try write(root + "/old/dist/a.js")
        try write(root + "/old/node_modules/x/dist/b.js")
        try write(root + "/fresh/package.json", age: 1)
        try write(root + "/fresh/dist/a.js")
        try write(root + "/loose/dist/a.js")           // no project marker
        try write(root + "/old/.git/logs/HEAD", age: 200)

        let category = ScanCategory(
            id: "t", label: "t", paths: [root], risk: .moderate, description: "",
            scan: .staleBuildArtifacts, findNames: StaleProjectPolicy.defaultArtifactNames, minAgeDays: 90
        )
        var deduper = DiskMeasurement.Deduper()
        let result = try StaleProjectArtifactScanner.measure(
            category: category, roots: [root], fileManager: fm, homeDirectory: home, deduper: &deduper
        )
        let found = result?.paths.map(\.path).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } ?? []
        let expected = URL(fileURLWithPath: root + "/old/dist").resolvingSymlinksInPath().path
        XCTAssertEqual(found, [expected])
        XCTAssertEqual(result?.paths.first?.isSelected, false)
    }
}
