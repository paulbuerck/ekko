import XCTest
@testable import Ekko

/// Aus der Nachbesserung im Zielfeld Wörterbuch-Regeln ableiten —
/// nur eindeutige, ähnliche Ersetzungen zwischen unveränderten Nachbarn.
final class KorrekturLernerTests: XCTestCase {
    private func regeln(_ eingefuegt: String, _ feld: String,
                        bekannt: Set<String> = []) -> [String] {
        KorrekturLerner.vorschlaege(eingefuegt: eingefuegt, feldtext: feld,
                                    bekannt: bekannt)
            .map { "\($0.falsch) -> \($0.richtig)" }
    }

    func testEinzelnesWortKorrigiert() {
        XCTAssertEqual(regeln("Ich gehe mit mueller spazieren.",
                              "Ich gehe mit Müller spazieren."),
                       ["mueller -> Müller"])
    }

    func testFeldEnthaeltMehrTextDrumherum() {
        XCTAssertEqual(regeln("Treffen mit Herrn mayer morgen",
                              "Hallo Team,\nTreffen mit Herrn Meyer morgen\nGruß Anna"),
                       ["mayer -> Meyer"])
    }

    func testZweiWorteZuEinem() {
        XCTAssertEqual(regeln("Wir nutzen whisper kit dafür",
                              "Wir nutzen WhisperKit dafür"),
                       ["whisper kit -> WhisperKit"])
    }

    func testInterpunktionZaehltNicht() {
        XCTAssertEqual(regeln("Das ist mueller, oder?",
                              "Das ist Müller, oder?"),
                       ["mueller -> Müller"])
    }

    func testNurGrossKleinschreibung() {
        XCTAssertEqual(regeln("Ich nutze sevdesk dafür",
                              "Ich nutze sevDesk dafür"),
                       ["sevdesk -> sevDesk"])
    }

    func testUnaehnlicheErsetzungIstStilNichtFehler() {
        // „morgen" → „übermorgen" ok, aber „Hund" → „Katze" ist inhaltlich.
        XCTAssertEqual(regeln("Ich gehe mit dem Hund raus",
                              "Ich gehe mit der Katze raus"), [])
    }

    func testWortErweiterungIstInhaltNichtErkennung() {
        XCTAssertEqual(regeln("Wir sehen uns morgen früh",
                              "Wir sehen uns übermorgen früh"), [])
    }

    func testUmgeschriebenerSatzLerntNichts() {
        XCTAssertEqual(regeln("Ich gehe morgen mit mueller spazieren",
                              "Spaziergang verschoben, Details folgen"), [])
    }

    func testNurErgaenztLerntNichts() {
        XCTAssertEqual(regeln("Ich komme morgen",
                              "Ich komme morgen gegen zehn"), [])
    }

    func testUnveraendertLerntNichts() {
        XCTAssertEqual(regeln("Alles gut so", "Alles gut so"), [])
    }

    func testRandWortMitEinemNachbarn() {
        XCTAssertEqual(regeln("mueller ist müde", "Müller ist müde"),
                       ["mueller -> Müller"])
    }

    func testBekannteRegelWirdNichtNochmalVorgeschlagen() {
        XCTAssertEqual(regeln("mit mueller raus", "mit Müller raus",
                              bekannt: ["mueller"]), [])
    }

    func testLeererFeldtext() {
        XCTAssertEqual(regeln("irgendwas", ""), [])
    }
}
