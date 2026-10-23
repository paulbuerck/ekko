import XCTest
@testable import Ekko

final class LiveKonfirmationTests: XCTestCase {
    func seg(_ text: String, _ ende: Float) -> LiveSegment {
        LiveSegment(text: text, ende: ende)
    }

    func testWenigeSegmenteBleibenHypothese() {
        var k = LiveKonfirmation()
        k.nimm([seg("Guten", 1), seg("Tag", 2)])
        XCTAssertEqual(k.bestaetigterText, "")
        XCTAssertEqual(k.hypothesenText, "Guten Tag")
        XCTAssertEqual(k.bestaetigtEnde, 0)
    }

    func testUeberzaehligeSegmenteWerdenBestaetigt() {
        var k = LiveKonfirmation()
        k.nimm([seg("Guten", 1), seg("Tag", 2), seg("Herr", 3)])
        XCTAssertEqual(k.bestaetigterText, "Guten")
        XCTAssertEqual(k.hypothesenText, "Tag Herr")
        XCTAssertEqual(k.bestaetigtEnde, 1)
    }

    func testBestaetigtWaechstNurVorwaerts() {
        var k = LiveKonfirmation()
        k.nimm([seg("Guten", 1), seg("Tag", 2), seg("Herr", 3)])
        // Nächster Pass liefert Segmente ab clipTimestamp — Ende früher
        // als bisher Bestätigtes darf nichts doppelt anhängen:
        k.nimm([seg("Tag", 0.5), seg("Herr", 2.5), seg("Petersen", 3.5)])
        XCTAssertEqual(k.bestaetigterText, "Guten")
        XCTAssertEqual(k.hypothesenText, "Herr Petersen")
    }

    func testMehrerePaesseSammelnBestaetigtes() {
        var k = LiveKonfirmation()
        k.nimm([seg("Guten", 1), seg("Tag", 2), seg("Herr", 3)])
        k.nimm([seg("Tag", 2), seg("Herr", 3), seg("Petersen,", 4),
                seg("vielen", 5)])
        XCTAssertEqual(k.bestaetigterText, "Guten Tag Herr")
        XCTAssertEqual(k.hypothesenText, "Petersen, vielen")
        XCTAssertEqual(k.bestaetigtEnde, 3)
    }

    func testAbschlussBestaetigtAlles() {
        var k = LiveKonfirmation()
        k.nimm([seg("Guten", 1), seg("Tag", 2), seg("Herr", 3)])
        k.schliesseAb(mit: [seg("Tag", 2), seg("Herr", 3),
                            seg("Petersen.", 4)])
        XCTAssertEqual(k.bestaetigterText, "Guten Tag Herr Petersen.")
        XCTAssertEqual(k.hypothesenText, "")
    }

    func testAbschlussOhneNeueSegmenteNimmtHypothese() {
        var k = LiveKonfirmation()
        k.nimm([seg("Guten", 1), seg("Tag", 2)])
        k.schliesseAb(mit: [])
        XCTAssertEqual(k.bestaetigterText, "Guten Tag")
        XCTAssertEqual(k.hypothesenText, "")
    }

    func testTextWirdGetrimmtUndVerbunden() {
        var k = LiveKonfirmation()
        k.nimm([seg(" Guten ", 1), seg("  Tag", 2), seg("Herr ", 3)])
        XCTAssertEqual(k.bestaetigterText, "Guten")
        XCTAssertEqual(k.hypothesenText, "Tag Herr")
    }
}
