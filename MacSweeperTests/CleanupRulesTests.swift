import XCTest
@testable import MacSweeper

final class CleanupRulesTests: XCTestCase {
    private let home = "/Users/tester"

    private func loadRules() throws -> [ScanCategory] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "cleanup-rules", withExtension: "json"))
        return try JSONDecoder().decode([ScanCategory].self, from: Data(contentsOf: url))
    }

    func testRuleIDsAreUnique() throws {
        let rules = try loadRules()
        XCTAssertEqual(Set(rules.map(\.id)).count, rules.count)
    }

    func testRulePathsStayInHomeOrApplications() throws {
        for rule in try loadRules() {
            for path in rule.paths {
                XCTAssertTrue(
                    path.hasPrefix("~/") || path.hasPrefix("/Applications"),
                    "\(rule.id): \(path)"
                )
            }
        }
    }

    func testSafeRulePathsPassTrashSafetyPolicy() throws {
        for rule in try loadRules() where rule.risk == .safe {
            for path in rule.paths where path.hasPrefix("~/") {
                let expanded = home + path.dropFirst(1)
                XCTAssertTrue(
                    PathSafetyPolicy.isAllowedToTrash(expanded, homeDirectory: home),
                    "\(rule.id): \(path)"
                )
            }
        }
    }

    func testMessagesAttachmentsAreNeverTrashable() {
        XCTAssertFalse(PathSafetyPolicy.isAllowedToTrash(
            home + "/Library/Messages/Attachments", homeDirectory: home
        ))
    }
}
