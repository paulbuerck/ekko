import XCTest
@testable import Ekko

final class TapDetectorTests: XCTestCase {
    func testHaltenIstStartDannStop() {
        var d = TapDetector()
        XCTAssertEqual(d.onFlags(down: true, at: 10.0), .start)
        XCTAssertEqual(d.onFlags(down: false, at: 11.5), .stop)
    }

    func testKurztippIstCancel() {
        var d = TapDetector()
        XCTAssertEqual(d.onFlags(down: true, at: 10.0), .start)
        XCTAssertEqual(d.onFlags(down: false, at: 10.2), .cancel)
    }

    func testDoppeltippNachKurztipp() {
        var d = TapDetector()
        _ = d.onFlags(down: true, at: 10.0)
        XCTAssertEqual(d.onFlags(down: false, at: 10.15), .cancel)
        XCTAssertEqual(d.onFlags(down: true, at: 10.3), .doubleTap)
        // Up nach Doppeltipp wird geschluckt:
        XCTAssertNil(d.onFlags(down: false, at: 10.4))
    }

    func testZuSpaeterZweiterTippIstNeuerStart() {
        var d = TapDetector()
        _ = d.onFlags(down: true, at: 10.0)
        _ = d.onFlags(down: false, at: 10.15)
        XCTAssertEqual(d.onFlags(down: true, at: 10.8), .start)
    }
}
