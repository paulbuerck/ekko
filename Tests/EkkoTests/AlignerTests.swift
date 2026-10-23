import XCTest
@testable import Ekko

final class AlignerTests: XCTestCase {
    let skript = """
    Guten Tag zusammen. Ich zeige euch heute, wie wir bei BÜRCK die
    Rechnungsstellung neu gedacht haben. Kein Umweg mehr über drei
    Systeme, keine Doppeleingaben.
    """

    func testFolgtExaktGesprochenem() {
        var a = Aligner(skript: skript)
        a.hoere("guten tag zusammen ich zeige")
        XCTAssertEqual(a.position, 5)  // nächstes zu sprechendes Wort
    }

    func testInterpunktionUndGrossschreibungEgal() {
        var a = Aligner(skript: skript)
        a.hoere("Guten, Tag! ZUSAMMEN?")
        XCTAssertEqual(a.position, 3)
    }

    func testAdLibHaeltPosition() {
        var a = Aligner(skript: skript)
        a.hoere("guten tag zusammen")
        let vorher = a.position
        a.hoere("guten tag zusammen äh übrigens schönes wetter draußen heute wirklich")
        XCTAssertEqual(a.position, vorher)  // wartet, läuft nicht weg
    }

    func testVersprecherUeberspringtEinWort() {
        var a = Aligner(skript: skript)
        // "ich zeige euch heute" — Sprecher lässt "euch" aus:
        a.hoere("guten tag zusammen ich zeige heute wie wir")
        // Fenster findet "heute/wie/wir" trotz Lücke → Position hinter "wir"
        XCTAssertEqual(a.position, 9)
    }

    func testKeinRueckwaertssprung() {
        var a = Aligner(skript: skript)
        a.hoere("guten tag zusammen ich zeige euch heute wie wir bei bürck")
        let weit = a.position
        // Hypothese schrumpft (STT revidiert) → Position bleibt:
        a.hoere("guten tag")
        XCTAssertEqual(a.position, weit)
    }

    func testWiederholteWoerterImSkript() {
        var a = Aligner(skript: "das Haus das Auto das Boot")
        a.hoere("das haus das")
        XCTAssertEqual(a.position, 3)  // zweites "das", nicht erstes
    }

    func testPositionSetzenManuell() {
        var a = Aligner(skript: skript)
        a.setzePosition(10)
        XCTAssertEqual(a.position, 10)
        a.hoere("systeme keine doppeleingaben")  // liegt weit hinter 10
        XCTAssertGreaterThanOrEqual(a.position, 10)
    }

    func testFortschritt() {
        var a = Aligner(skript: "eins zwei drei vier")
        XCTAssertEqual(a.fortschritt, 0)
        a.hoere("eins zwei")
        XCTAssertEqual(a.fortschritt, 0.5, accuracy: 0.01)
    }

    func testFertig() {
        var a = Aligner(skript: "eins zwei drei")
        a.hoere("eins zwei drei")
        XCTAssertEqual(a.position, 3)
        XCTAssertEqual(a.fortschritt, 1.0, accuracy: 0.01)
    }
}
