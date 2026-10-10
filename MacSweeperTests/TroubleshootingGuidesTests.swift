import XCTest
@testable import MacSweeper

final class TroubleshootingGuidesTests: XCTestCase {
    func testGuidesDecodeAndAreComplete() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "troubleshooting-guides", withExtension: "json"))
        let guides = try TroubleshootingGuides.decode(Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(guides.count, 5)
        XCTAssertEqual(Set(guides.map(\.id)).count, guides.count)
        for g in guides {
            XCTAssertFalse(g.commands.isEmpty, g.id)
            XCTAssertFalse(g.commands.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }, g.id)
            XCTAssertFalse(g.whenItHelps.isEmpty, g.id)
            XCTAssertFalse(g.whenItWontHelp.isEmpty, g.id)
        }
    }
}
