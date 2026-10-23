import XCTest
@testable import Ekko

@MainActor
final class WoerterbuchEditorTests: XCTestCase {
    private func tempEditor() -> (WoerterbuchEditor, URL) {
        let datei = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        return (WoerterbuchEditor(pfad: datei), datei)
    }

    func testHinzufuegenUndLadenRoundTrip() throws {
        let (ed, datei) = tempEditor()
        try ed.hinzufuegen(falsch: "bürk", richtig: "BÜRCK")
        let neu = WoerterbuchEditor(pfad: datei)
        neu.lade()
        XCTAssertEqual(neu.regeln.count, 1)
        XCTAssertEqual(neu.regeln[0].falsch, "bürk")
        XCTAssertEqual(neu.regeln[0].richtig, "BÜRCK")
    }

    func testBearbeitenAendertRegelUndPersistiert() throws {
        let (ed, datei) = tempEditor()
        try ed.hinzufuegen(falsch: "bürk", richtig: "BÜRK")
        try ed.bearbeiten(index: 0, falsch: "bürck", richtig: "BÜRCK")
        XCTAssertEqual(ed.regeln[0].falsch, "bürck")
        XCTAssertEqual(ed.regeln[0].richtig, "BÜRCK")
        let neu = WoerterbuchEditor(pfad: datei)
        neu.lade()
        XCTAssertEqual(neu.regeln.count, 1)
        XCTAssertEqual(neu.regeln[0].richtig, "BÜRCK")
    }

    func testBearbeitenMitLeerWirdIgnoriert() throws {
        let (ed, _) = tempEditor()
        try ed.hinzufuegen(falsch: "a", richtig: "A")
        try ed.bearbeiten(index: 0, falsch: "a", richtig: "  ")
        XCTAssertEqual(ed.regeln[0].richtig, "A")
    }

    func testLoeschen() throws {
        let (ed, _) = tempEditor()
        try ed.hinzufuegen(falsch: "a", richtig: "A")
        try ed.hinzufuegen(falsch: "b", richtig: "B")
        try ed.loesche(index: 0)
        XCTAssertEqual(ed.regeln.map(\.falsch), ["b"])
    }

    func testRichtigMitPfeilWirdNichtVerworfen() throws {
        let (ed, datei) = tempEditor()
        try ed.hinzufuegen(falsch: "pfeil", richtig: "a -> b")
        let neu = WoerterbuchEditor(pfad: datei)
        neu.lade()
        XCTAssertEqual(neu.regeln.count, 1)
        XCTAssertEqual(neu.regeln[0].falsch, "pfeil")
        XCTAssertEqual(neu.regeln[0].richtig, "a -> b")
    }
}
