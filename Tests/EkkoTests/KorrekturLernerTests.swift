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
        XCTAssertEqual(regeln("Ich gehe mit schieba spazieren.",
                              "Ich gehe mit Shiba spazieren."),
                       ["schieba -> Shiba"])
    }

    func testFeldEnthaeltMehrTextDrumherum() {
        XCTAssertEqual(regeln("Treffen mit Herrn bürk morgen",
                              "Hallo Team,\nTreffen mit Herrn Bürck morgen\nGruß Paul"),
                       ["bürk -> Bürck"])
    }

    func testZweiWorteZuEinem() {
        XCTAssertEqual(regeln("Wir nutzen whisper kit dafür",
                              "Wir nutzen WhisperKit dafür"),
                       ["whisper kit -> WhisperKit"])
    }

    func testInterpunktionZaehltNicht() {
        XCTAssertEqual(regeln("Das ist schieba, oder?",
                              "Das ist Shiba, oder?"),
                       ["schieba -> Shiba"])
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
        XCTAssertEqual(regeln("Ich gehe morgen mit schieba spazieren",
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
        XCTAssertEqual(regeln("schieba ist müde", "Shiba ist müde"),
                       ["schieba -> Shiba"])
    }

    func testBekannteRegelWirdNichtNochmalVorgeschlagen() {
        XCTAssertEqual(regeln("mit schieba raus", "mit Shiba raus",
                              bekannt: ["schieba"]), [])
    }

    func testLeererFeldtext() {
        XCTAssertEqual(regeln("irgendwas", ""), [])
    }
}
