import XCTest
@testable import MacSweeper

final class CleanupAllowlistTests: XCTestCase {
    private var home: String!
    private var service: CleanupService!

    override func setUp() async throws {
        home = "/Users/testuser"
        service = CleanupService(fileManager: .default, homeDirectory: home)
    }

    func testDeniesOutsideHome() async {
        let allowed = await service.isAllowedToTrash("/tmp/something")
        XCTAssertFalse(allowed)
    }

    func testDeniesHomeRoot() async {
        let allowed = await service.isAllowedToTrash(home)
        XCTAssertFalse(allowed)
    }

    func testDeniesLibraryRoot() async {
        let allowed = await service.isAllowedToTrash(home + "/Library")
        XCTAssertFalse(allowed)
    }

    func testDeniesTrashFolderItself() async {
        let allowed = await service.isAllowedToTrash(home + "/.Trash")
        XCTAssertFalse(allowed)
    }

    func testDeniesDocuments() async {
        let allowed = await service.isAllowedToTrash(home + "/Documents/report.pdf")
        XCTAssertFalse(allowed)
    }

    func testDeniesDesktop() async {
        let allowed = await service.isAllowedToTrash(home + "/Desktop/notes.txt")
        XCTAssertFalse(allowed)
    }

    func testAllowsNodeModulesUnderDocuments() async {
        let allowed = await service.isAllowedToTrash(home + "/Documents/proj/node_modules")
        XCTAssertTrue(allowed)
    }

    func testAllowsVenvUnderDesktop() async {
        let allowed = await service.isAllowedToTrash(home + "/Desktop/proj/.venv")
        XCTAssertTrue(allowed)
    }

    func testAllowsLibraryCaches() async {
        let allowed = await service.isAllowedToTrash(home + "/Library/Caches/SomeApp")
        XCTAssertTrue(allowed)
    }

    func testDeniesKeychains() async {
        let allowed = await service.isAllowedToTrash(home + "/Library/Keychains/login.keychain-db")
        XCTAssertFalse(allowed)
    }

    func testAllowsDownloads() async {
        let allowed = await service.isAllowedToTrash(home + "/Downloads/old.dmg")
        XCTAssertTrue(allowed)
    }
}

final class RunningAppSafetyTests: XCTestCase {
    func testProtectsBundlePath() {
        let bundle = RunningAppSafety.bundlePath
        XCTAssertTrue(RunningAppSafety.isProtected(bundle))
    }

    func testProtectsAncestorOfBundle() {
        let bundle = RunningAppSafety.bundlePath
        let parent = (bundle as NSString).deletingLastPathComponent
        XCTAssertTrue(RunningAppSafety.isProtected(parent))
    }

    func testProtectsChildOfBundle() {
        let child = RunningAppSafety.bundlePath + "/Contents/Info.plist"
        XCTAssertTrue(RunningAppSafety.isProtected(child))
    }

    func testUnrelatedPathNotProtected() {
        XCTAssertFalse(RunningAppSafety.isProtected("/tmp/unrelated-folder"))
    }
}

final class TrashRestoreTests: XCTestCase {
    private var tempRoot: URL!
    private var fakeHome: String!
    private var fileManager: FakeTrashFileManager!
    private var service: CleanupService!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSweeperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        fakeHome = tempRoot.path
        let trash = tempRoot.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        fileManager = FakeTrashFileManager(trashDirectory: trash)
        service = CleanupService(fileManager: fileManager, homeDirectory: fakeHome)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testMoveToTrashThenRestore() async throws {
        let caches = tempRoot.appendingPathComponent("Library/Caches/TestCache", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let file = caches.appendingPathComponent("blob.dat")
        try Data("hello".utf8).write(to: file)

        let category = ScanCategory(
            id: "user_app_caches",
            label: "App caches",
            paths: ["~/Library/Caches"],
            risk: .safe,
            description: "test"
        )
        let result = ScanResult(
            category: category,
            paths: [ScannedPath(path: file.path, byteCount: 5, isSelected: true)],
            isSelected: true
        )

        let outcome = try await service.moveToTrash([result])
        XCTAssertEqual(outcome.itemCount, 1)
        XCTAssertEqual(outcome.failures.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(outcome.moved.count, 1)

        let restore = try await service.restoreFromTrash(outcome.moved)
        XCTAssertEqual(restore.itemCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testRestoreFailsWhenOriginalExists() async throws {
        let original = tempRoot.appendingPathComponent("Library/Caches/exists.txt")
        try FileManager.default.createDirectory(
            at: original.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("a".utf8).write(to: original)

        let trashCopy = tempRoot.appendingPathComponent(".Trash/exists.txt")
        try Data("b".utf8).write(to: trashCopy)

        let item = CleanupService.MovedItem(
            categoryID: "test",
            originalPath: original.path,
            trashURL: trashCopy,
            byteCount: 1
        )
        let restore = try await service.restoreFromTrash([item])
        XCTAssertEqual(restore.itemCount, 0)
        XCTAssertEqual(restore.failures.count, 1)
        XCTAssertTrue(restore.failures[0].message.contains("already exists"))
    }

    func testEmptyTrashOnlyDeletesUnderTrash() async throws {
        let trashItem = tempRoot.appendingPathComponent(".Trash/gone.txt")
        try Data("x".utf8).write(to: trashItem)
        let keep = tempRoot.appendingPathComponent("Library/Caches/keep.txt")
        try FileManager.default.createDirectory(
            at: keep.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("y".utf8).write(to: keep)

        let outcome = try await service.emptyTrashContents(byteHint: 100)
        XCTAssertTrue(outcome.emptiedTrash)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashItem.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
    }

    func testProtectedPathIsNotTrashed() async throws {
        let docs = tempRoot.appendingPathComponent("Documents/secret.txt")
        try FileManager.default.createDirectory(
            at: docs.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("nope".utf8).write(to: docs)

        let category = ScanCategory(
            id: "old_downloads",
            label: "Downloads",
            paths: ["~/Downloads"],
            risk: .moderate,
            description: "test"
        )
        let result = ScanResult(
            category: category,
            paths: [ScannedPath(path: docs.path, byteCount: 4, isSelected: true)],
            isSelected: true
        )
        let outcome = try await service.moveToTrash([result])
        XCTAssertEqual(outcome.itemCount, 0)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: docs.path))
    }
}

/// Routes `trashItem` into a fake `~/.Trash` for isolated tests.
final class FakeTrashFileManager: FileManager, @unchecked Sendable {
    let trashDirectory: URL

    init(trashDirectory: URL) {
        self.trashDirectory = trashDirectory
        super.init()
    }

    override func trashItem(
        at url: URL,
        resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
    ) throws {
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        var dest = trashDirectory.appendingPathComponent(url.lastPathComponent)
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = trashDirectory.appendingPathComponent("\(url.lastPathComponent).\(n)")
            n += 1
        }
        try FileManager.default.moveItem(at: url, to: dest)
        outResultingURL?.pointee = dest as NSURL
    }
}

final class RuleCoverageTests: XCTestCase {
    func testFixedRuleMatch() {
        let category = ScanCategory(
            id: "browser_chrome_cache",
            label: "Chrome cache",
            paths: ["~/Library/Caches/Google/Chrome"],
            risk: .safe,
            description: "test"
        )
        let home = "/Users/testuser"
        let path = home + "/Library/Caches/Google/Chrome/Default"
        let match = RuleCoverage.matchInCategories(
            path: path,
            categories: [category],
            homeDirectory: home
        )
        XCTAssertEqual(match?.categoryID, "browser_chrome_cache")
    }

    func testFindNamedDirsMatch() {
        let category = ScanCategory(
            id: "dev_node_modules",
            label: "node_modules",
            paths: ["~/Developer"],
            risk: .risky,
            description: "test",
            group: "dev",
            scan: .findNamedDirs,
            findNames: ["node_modules"]
        )
        let home = "/Users/testuser"
        let path = home + "/Developer/app/node_modules"
        let match = RuleCoverage.matchInCategories(
            path: path,
            categories: [category],
            homeDirectory: home
        )
        XCTAssertEqual(match?.categoryID, "dev_node_modules")
    }

    func testScanResultsPreferred() {
        let category = ScanCategory(
            id: "user_logs",
            label: "Logs",
            paths: ["~/Library/Logs"],
            risk: .safe,
            description: "test"
        )
        let result = ScanResult(
            category: category,
            paths: [
                ScannedPath(
                    path: "/Users/testuser/Library/Logs/SomeApp",
                    byteCount: 10,
                    isSelected: true
                )
            ],
            isSelected: true
        )
        let match = RuleCoverage.match(
            path: "/Users/testuser/Library/Logs/SomeApp/error.log",
            scanResults: [result],
            categories: [],
            homeDirectory: "/Users/testuser"
        )
        XCTAssertEqual(match?.categoryID, "user_logs")
    }
}

final class ScanResultSelectionTests: XCTestCase {
    func testSelectingOnlyCheckedPaths() {
        let category = ScanCategory(
            id: "old_downloads",
            label: "Downloads",
            paths: ["~/Downloads"],
            risk: .moderate,
            description: "test",
            scan: .listChildren
        )
        var result = ScanResult(
            category: category,
            paths: [
                ScannedPath(path: "/Users/a/Downloads/a.zip", byteCount: 1, isSelected: true),
                ScannedPath(path: "/Users/a/Downloads/b.zip", byteCount: 2, isSelected: false),
            ],
            isSelected: true
        )
        let selected = result.selectingOnlyCheckedPaths()
        XCTAssertEqual(selected?.paths.count, 1)
        XCTAssertEqual(selected?.paths.first?.path, "/Users/a/Downloads/a.zip")

        result.setAllPathsSelected(false)
        XCTAssertNil(result.selectingOnlyCheckedPaths())
    }
}
