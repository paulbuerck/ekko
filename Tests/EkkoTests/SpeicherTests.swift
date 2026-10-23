import XCTest
@testable import Ekko

final class SpeicherTests: XCTestCase {
    func testResidentSpeicherIstPlausibel() {
        let mb = residentSpeicherMB()
        // Ein laufender Testprozess belegt zweistellige MB, nie 0 oder riesig.
        XCTAssertGreaterThan(mb, 1)
        XCTAssertLessThan(mb, 100_000)
    }
}
