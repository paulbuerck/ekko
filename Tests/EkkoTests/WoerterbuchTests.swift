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
        let wb = try mitRegeln("bürk -> BÜRCK\n")
        XCTAssertEqual(wb.apply("Die bürk App."), "Die BÜRCK App.")
        XCTAssertEqual(wb.apply("bürkchen"), "bürkchen")  // kein Teilwort
    }

    func testCaseInsensitiv() throws {
        let wb = try mitRegeln("bürk -> BÜRCK\n")
        XCTAssertEqual(wb.apply("Bürk und BÜRK"), "BÜRCK und BÜRCK")
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
