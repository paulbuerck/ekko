import XCTest
@testable import Ekko

final class StilProfilTests: XCTestCase {
    let zuordnungen = [
        ProfilZuordnung(bundleId: "com.apple.mail", art: .foermlich),
        ProfilZuordnung(bundleId: "md.obsidian", art: .strukturiert,
                        eigenerPrompt: "Mein Spezial-Prompt"),
    ]

    func testLookupFindetZuordnung() {
        let z = StilProfil.finde("com.apple.mail", in: zuordnungen)
        XCTAssertEqual(z?.art, .foermlich)
    }

    func testLookupUnbekannteAppErgibtNil() {
        XCTAssertNil(StilProfil.finde("com.example.fremd", in: zuordnungen))
        XCTAssertNil(StilProfil.finde(nil, in: zuordnungen))
    }

    func testEigenerPromptGewinnt() {
        let z = StilProfil.finde("md.obsidian", in: zuordnungen)
        XCTAssertEqual(z?.wirksameAnweisung, "Mein Spezial-Prompt")
    }

    func testStandardPromptJeArt() {
        for art in StilArt.allCases where art != .standard {
            XCTAssertFalse(art.anweisung.isEmpty,
                           "\(art) braucht eine Anweisung")
        }
    }

    func testVorbelegungDecktKernApps() {
        let arten = Dictionary(
            uniqueKeysWithValues: ProfilZuordnung.vorbelegt.map {
                ($0.bundleId, $0.art)
            })
        XCTAssertEqual(arten["com.apple.mail"], .foermlich)
        XCTAssertEqual(arten["md.obsidian"], .strukturiert)
        XCTAssertEqual(arten["com.apple.Notes"], .strukturiert)
        XCTAssertEqual(arten["com.apple.MobileSMS"], .knapp)
        XCTAssertEqual(arten["com.tinyspeck.slackmacgap"], .knapp)
    }

    // Lockere Guardrail (Stil-Profile dürfen umformulieren): nur
    // Leer-Check + Längen-Ratio, KEINE Wort-Überlappung.
    func testLockerLeerFaelltZurueck() {
        XCTAssertEqual(Cleanup.validateLocker(roh: "Hallo Welt", sauber: " "),
                       "Hallo Welt")
    }

    func testLockerUmformulierungAkzeptiert() {
        // Kaum Wort-Überlappung, Länge okay → durchlassen (strenge
        // Guardrail würde das verwerfen).
        let roh = "hey schick mir das mal rüber bitte"
        let sauber = "Könnten Sie mir die Unterlagen bitte zusenden?"
        XCTAssertEqual(Cleanup.validateLocker(roh: roh, sauber: sauber), sauber)
    }

    func testLockerWucherungFaelltZurueck() {
        let roh = "kurzer Satz"
        let lang = String(repeating: "bla ", count: 50)
        XCTAssertEqual(Cleanup.validateLocker(roh: roh, sauber: lang), roh)
    }

    func testLockerKollapsFaelltZurueck() {
        let roh = String(repeating: "viele Wörter ", count: 20)
        XCTAssertEqual(Cleanup.validateLocker(roh: roh, sauber: "Ok."), roh)
    }

    // „Fragen bleiben Fragen": das Modell
    // darf eine diktierte Frage nicht beantworten statt umzuformulieren.
    func testLockerFrageBleibtFrage() {
        let roh = "Sollen wir das auf Montag verschieben?"
        let antwort = "Ja, lass uns das auf Montag verschieben."
        XCTAssertEqual(Cleanup.validateLocker(roh: roh, sauber: antwort), roh)
    }

    func testLockerFrageAlsFrageUmformuliert() {
        let roh = "Sollen wir das auf Montag verschieben?"
        let frage = "Wäre eine Verschiebung auf Montag möglich?"
        XCTAssertEqual(Cleanup.validateLocker(roh: roh, sauber: frage), frage)
    }

    func testLockerKontextAusnahmeUnechteFrage() {
        // »?« ohne Frage-Signalwort im letzten Satz = vermutlich
        // Transkriptions-Interpunktion → Umformulierung durchlassen.
        let roh = "Na dann machen wir das eben so?"
        let sauber = "Gut, dann machen wir das so."
        XCTAssertEqual(Cleanup.validateLocker(roh: roh, sauber: sauber), sauber)
    }

    func testLockerAussageZurFrageBleibtErlaubt() {
        // Gegenrichtung bleibt legitime Umformulierung (förmlich).
        let roh = "hey schick mir das mal rüber bitte"
        let frage = "Könnten Sie mir die Unterlagen bitte zusenden?"
        XCTAssertEqual(Cleanup.validateLocker(roh: roh, sauber: frage), frage)
    }
}
