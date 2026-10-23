import XCTest
@testable import Ekko

final class TranskriptAblageTests: XCTestCase {
    func testDateiNameEntferntPfadZeichen() {
        let n = TranskriptAblage.dateiName("AC/DC: Live? 100%")
        XCTAssertFalse(n.contains("/"))
        XCTAssertFalse(n.contains(":"))
        XCTAssertFalse(n.contains("?"))
        XCTAssertFalse(n.contains("%"))
    }

    func testDateiNameKapptAuf80() {
        let lang = String(repeating: "a", count: 200)
        XCTAssertLessThanOrEqual(TranskriptAblage.dateiName(lang).count, 80)
    }

    func testDateiNameFallbackBeiLeer() {
        XCTAssertEqual(TranskriptAblage.dateiName("   "), "transkript")
        XCTAssertEqual(TranskriptAblage.dateiName("///"), "transkript")
    }

    func testDateiNameBehaeltNormalenTitel() {
        XCTAssertEqual(TranskriptAblage.dateiName("Mein Video"), "Mein Video")
    }
}
