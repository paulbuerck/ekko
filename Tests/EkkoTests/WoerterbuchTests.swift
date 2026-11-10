import XCTest
@testable import Ekko

@MainActor
final class WoerterbuchTests: XCTestCase {
    private func mitRegeln(_ inhalt: String) throws -> Woerterbuch {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let datei = dir.appendingPathComponent("woerterbuch.txt")
        try inhalt.write(to: datei, atomically: true, encoding: .utf8)
        return Woerterbuch(pfad: datei)
    }

    func testErsetztMitWortgrenzen() throws {
        let wb = try mitRegeln("müler -> MÜLLER\n")
        XCTAssertEqual(wb.apply("Die müler App."), "Die MÜLLER App.")
        XCTAssertEqual(wb.apply("mülerchen"), "mülerchen")  // kein Teilwort
    }

    func testCaseInsensitiv() throws {
        let wb = try mitRegeln("müler -> MÜLLER\n")
        XCTAssertEqual(wb.apply("Müler und MÜLER"), "MÜLLER und MÜLLER")
    }

    func testKommentareUndKaputteZeilen() throws {
        let wb = try mitRegeln("# Kommentar\n\nkaputt ohne pfeil\nok -> OK\n")
        XCTAssertEqual(wb.apply("ok"), "OK")
    }

    func testFehlendeDateiIstNoop() {
        let wb = Woerterbuch(pfad: URL(fileURLWithPath: "/gibt/es/nicht.txt"))
        XCTAssertEqual(wb.apply("unverändert"), "unverändert")
    }
}
