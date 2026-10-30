import AppKit
import XCTest
@testable import MacSweeper

final class IconSetTests: XCTestCase {
    private func loadRules() throws -> [ScanCategory] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "cleanup-rules", withExtension: "json"))
        return try JSONDecoder().decode([ScanCategory].self, from: Data(contentsOf: url))
    }

    func testEveryRuleHasACustomIcon() throws {
        for rule in try loadRules() {
            XCTAssertNotNil(MSIcon.forCategory(id: rule.id), "\(rule.id) has no MSIcon mapping")
        }
    }

    func testEveryIconHasAnAsset() {
        for icon in MSIcon.allCases {
            XCTAssertNotNil(NSImage(named: icon.assetName), "missing asset \(icon.assetName)")
        }
    }
}
