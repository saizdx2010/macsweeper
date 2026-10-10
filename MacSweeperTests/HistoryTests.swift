import XCTest
@testable import MacSweeper

final class HistoryTests: XCTestCase {
    @MainActor
    func testDiffThresholdAndUnknownCategories() {
        let snapshot = AuditLogService.ScanSnapshot(timestamp: Date(), sizes: ["cache": 100_000_000])
        XCTAssertNil(snapshot.change(categoryID: "cache", bytes: 149_999_999))
        XCTAssertEqual(snapshot.change(categoryID: "cache", bytes: 150_000_000), 50_000_000)
        XCTAssertEqual(snapshot.change(categoryID: "cache", bytes: 50_000_000), -50_000_000)
        XCTAssertNil(snapshot.change(categoryID: "new", bytes: 900_000_000))
    }

    @MainActor
    func testLifetimeAggregation() {
        XCTAssertNil(AuditLogService.LifetimeSummary.aggregate([]))
        let early = Date(timeIntervalSince1970: 100)
        let entries = [
            AuditLogService.Entry(timestamp: early.addingTimeInterval(100), categoryID: "a", path: "a", byteCount: 300, destination: "trash"),
            AuditLogService.Entry(timestamp: early, categoryID: "b", path: "b", byteCount: 200, destination: "trash")
        ]
        let total = AuditLogService.LifetimeSummary.aggregate(entries)
        XCTAssertEqual(total?.freedBytes, 500)
        XCTAssertEqual(total?.firstDate, early)
    }

    func testRestoreOnlyRecordedItemsAndReportPartialFailure() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let trash = root.appendingPathComponent(".Trash")
        let restored = trash.appendingPathComponent("restore")
        let blocked = trash.appendingPathComponent("blocked")
        let unrelated = trash.appendingPathComponent("unrelated")
        for url in [restored, blocked, unrelated] { try Data("trash".utf8).write(to: url) }
        let occupied = root.appendingPathComponent("occupied")
        try Data("keep".utf8).write(to: occupied)
        let destination = root.appendingPathComponent("Caches/restored")
        let items = [
            CleanupService.MovedItem(categoryID: "a", originalPath: destination.path, trashURL: restored, byteCount: 100),
            CleanupService.MovedItem(categoryID: "a", originalPath: occupied.path, trashURL: blocked, byteCount: 200),
            CleanupService.MovedItem(categoryID: "a", originalPath: root.appendingPathComponent("missing").path, trashURL: trash.appendingPathComponent("gone"), byteCount: 300)
        ]
        let outcome = try await CleanupService(homeDirectory: root.path).restoreFromTrash(items)
        XCTAssertEqual(outcome.itemCount, 1)
        XCTAssertEqual(outcome.freedBytes, 100)
        XCTAssertEqual(outcome.failures.count, 2)
        XCTAssertTrue(fm.fileExists(atPath: destination.path))
        XCTAssertTrue(fm.fileExists(atPath: blocked.path))
        XCTAssertTrue(fm.fileExists(atPath: unrelated.path))
        XCTAssertEqual(try String(contentsOf: occupied), "keep")
    }

    func testRestoreDoesNotOverwriteDanglingSymlink() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("trash-item")
        try Data("item".utf8).write(to: source)
        let destination = root.appendingPathComponent("occupied")
        try fm.createSymbolicLink(atPath: destination.path, withDestinationPath: root.appendingPathComponent("absent").path)
        let item = CleanupService.MovedItem(categoryID: "a", originalPath: destination.path, trashURL: source, byteCount: 100)
        let outcome = try await CleanupService(homeDirectory: root.path).restoreFromTrash([item])
        XCTAssertEqual(outcome.itemCount, 0)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: source.path))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: destination.path), root.appendingPathComponent("absent").path)
    }
}
