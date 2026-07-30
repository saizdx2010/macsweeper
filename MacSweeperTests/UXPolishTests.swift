import XCTest
@testable import MacSweeper

final class UXPolishTests: XCTestCase {
    // MARK: - DetailPathQuery

    func testSearchMatchesNameAndPath() {
        let item = ScannedPath(
            path: "/Users/me/Downloads/Installer.dmg",
            byteCount: 100,
            isSelected: true
        )
        XCTAssertTrue(DetailPathQuery.matchesSearch(item, query: "installer"))
        XCTAssertTrue(DetailPathQuery.matchesSearch(item, query: "Downloads"))
        XCTAssertFalse(DetailPathQuery.matchesSearch(item, query: "node_modules"))
        XCTAssertTrue(DetailPathQuery.matchesSearch(item, query: "  "))
    }

    func testDisplayedPathsPaging() {
        let paths = (0..<5).map {
            ScannedPath(path: "/tmp/\($0)", byteCount: Int64($0), isSelected: true)
        }
        XCTAssertEqual(DetailPathQuery.displayedPaths(paths, limit: 2).count, 2)
        XCTAssertEqual(DetailPathQuery.omittedCount(total: 5, limit: 2), 3)
        XCTAssertEqual(DetailPathQuery.omittedCount(total: 2, limit: 10), 0)
    }

    // MARK: - CleanConfirmPolicy

    func testConfirmRequiredForRisky() {
        let risky = ScanResult(
            category: ScanCategory(
                id: "dev_node_modules",
                label: "node_modules",
                paths: ["~/Developer"],
                risk: .risky,
                description: "test"
            ),
            paths: [ScannedPath(path: "/Users/me/Developer/app/node_modules", byteCount: 10, isSelected: true)],
            isSelected: true
        )
        XCTAssertTrue(CleanConfirmPolicy.requiresConfirmation(results: [risky]))
    }

    func testConfirmRequiredForEmptyTrash() {
        let trash = ScanResult(
            category: ScanCategory(
                id: "empty_trash",
                label: "Empty Trash",
                paths: ["~/.Trash"],
                risk: .moderate,
                description: "test",
                action: .emptyTrash
            ),
            paths: [ScannedPath(path: "/Users/me/.Trash/a", byteCount: 10, isSelected: true)],
            isSelected: true
        )
        XCTAssertTrue(CleanConfirmPolicy.requiresConfirmation(results: [trash]))
    }

    func testConfirmNotRequiredForSafeOnly() {
        let safe = ScanResult(
            category: ScanCategory(
                id: "user_logs",
                label: "User logs",
                paths: ["~/Library/Logs"],
                risk: .safe,
                description: "test"
            ),
            paths: [ScannedPath(path: "/Users/me/Library/Logs/app.log", byteCount: 10, isSelected: true)],
            isSelected: true
        )
        XCTAssertFalse(CleanConfirmPolicy.requiresConfirmation(results: [safe]))
    }

    func testConfirmNotRequiredForSmallModerateOnly() {
        let moderate = ScanResult(
            category: ScanCategory(
                id: "old_downloads",
                label: "Downloads",
                paths: ["~/Downloads"],
                risk: .moderate,
                description: "test",
                scan: .listChildren
            ),
            paths: [ScannedPath(path: "/Users/me/Downloads/a.zip", byteCount: 10, isSelected: true)],
            isSelected: true
        )
        XCTAssertFalse(CleanConfirmPolicy.requiresConfirmation(results: [moderate]))
    }

    func testConfirmRequiredForLargeModerate() {
        let moderate = ScanResult(
            category: ScanCategory(
                id: "old_downloads",
                label: "Downloads",
                paths: ["~/Downloads"],
                risk: .moderate,
                description: "test",
                scan: .listChildren
            ),
            paths: [
                ScannedPath(
                    path: "/Users/me/Downloads/big.dmg",
                    byteCount: CleanConfirmPolicy.moderateByteThreshold,
                    isSelected: true
                )
            ],
            isSelected: true
        )
        XCTAssertTrue(CleanConfirmPolicy.requiresConfirmation(results: [moderate]))
        XCTAssertEqual(
            CleanConfirmPolicy.confirmationReason(results: [moderate]),
            .largeModerate(bytes: CleanConfirmPolicy.moderateByteThreshold)
        )
    }

    func testDetailFiltersMatchAgeAndSize() {
        let old = ScannedPath(
            path: "/Users/me/Downloads/old.zip",
            byteCount: 200_000_000,
            isSelected: true,
            contentModificationDate: Date().addingTimeInterval(-40 * 24 * 60 * 60)
        )
        XCTAssertTrue(DetailPathQuery.matchesFilters(old, age: .older30, size: .over100MB))
        XCTAssertFalse(DetailPathQuery.matchesFilters(old, age: .older90, size: .any))
        XCTAssertFalse(DetailPathQuery.matchesFilters(old, age: .any, size: .over1GB))
    }

    func testCategoryIconPrefersJSONField() {
        let withIcon = ScanCategory(
            id: "custom",
            label: "Custom",
            paths: [],
            risk: .safe,
            description: "test",
            icon: "globe"
        )
        XCTAssertEqual(withIcon.sfSymbolName, "globe")
        let without = ScanCategory(
            id: "custom",
            label: "Custom",
            paths: [],
            risk: .safe,
            description: "test"
        )
        XCTAssertEqual(without.sfSymbolName, "folder")
    }

    // MARK: - CategoryLabelResolver

    func testLabelPrefersStoredThenMapThenFallback() {
        XCTAssertEqual(
            CategoryLabelResolver.displayLabel(
                categoryID: "user_logs",
                storedLabel: "User logs",
                labelsByID: [:]
            ),
            "User logs"
        )
        XCTAssertEqual(
            CategoryLabelResolver.displayLabel(
                categoryID: "user_logs",
                storedLabel: nil,
                labelsByID: ["user_logs": "Logs"]
            ),
            "Logs"
        )
        XCTAssertEqual(
            CategoryLabelResolver.displayLabel(
                categoryID: "user_logs",
                storedLabel: nil,
                labelsByID: [:]
            ),
            "User Logs"
        )
    }

    // MARK: - ScanSession bulk select

    @MainActor
    func testBulkSelectHelpers() {
        let session = ScanSession()
        session.results = [
            ScanResult(
                category: ScanCategory(
                    id: "safe_a",
                    label: "Safe A",
                    paths: ["~/Library/Caches/a"],
                    risk: .safe,
                    description: "a"
                ),
                paths: [ScannedPath(path: "/Users/me/Library/Caches/a", byteCount: 5, isSelected: false)],
                isSelected: false
            ),
            ScanResult(
                category: ScanCategory(
                    id: "risky_b",
                    label: "Risky B",
                    paths: ["~/Developer"],
                    risk: .risky,
                    description: "b"
                ),
                paths: [ScannedPath(path: "/Users/me/Developer/x/node_modules", byteCount: 9, isSelected: true)],
                isSelected: true
            ),
        ]

        session.selectWhere(risk: .safe)
        XCTAssertTrue(session.results[0].isSelected)
        XCTAssertTrue(session.results[0].paths[0].isSelected)

        session.deselectWhere(risk: .risky)
        XCTAssertFalse(session.results[1].isSelected)
        XCTAssertFalse(session.results[1].paths[0].isSelected)

        session.selectWhere(risk: .safe)
        session.deselectAll()
        XCTAssertFalse(session.results[0].isSelected)
        XCTAssertFalse(session.results[1].isSelected)
    }
}
