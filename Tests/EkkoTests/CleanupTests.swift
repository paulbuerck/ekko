import XCTest
@testable import Ekko

final class CleanupTests: XCTestCase {
    let roh = "Ähm, also der Termin ist am Dienstag, nein, Mittwoch um 14 Uhr."

    func testPlausibleKuerzungAkzeptiert() {
        let sauber = "Der Termin ist am Mittwoch um 14 Uhr."
        XCTAssertEqual(Cleanup.validate(roh: roh, sauber: sauber), sauber)
    }
    func testLeerFaelltAufRohZurueck() {
        XCTAssertEqual(Cleanup.validate(roh: roh, sauber: "  "), roh)
    }
    func testKollapsFaelltAufRohZurueck() {
        XCTAssertEqual(Cleanup.validate(roh: roh, sauber: "Mittwoch."), roh)
    }
    func testWucherungFaelltAufRohZurueck() {
        let lang = String(repeating: "x", count: roh.count * 2)
        XCTAssertEqual(Cleanup.validate(roh: roh, sauber: lang), roh)
    }
    func testChatAntwortFaelltAufRohZurueck() {
        // LLM beantwortet das Diktat statt es zu bereinigen — ähnliche
        // Länge (Ratio ok), aber kaum geteilte Wörter → Rohtext gewinnt.
        let chat = "Hallo, ich bin hier, um dir zu helfen. Was möchtest du?"
        XCTAssertEqual(Cleanup.validate(roh: roh, sauber: chat), roh)
    }

    // „Fragen bleiben Fragen" auch im Standard-Putzen: eine Antwort auf
    // die diktierte Frage teilt viele Wörter und passiert die
    // Überlappungs-Prüfung — der Frage-Guard fängt sie.
    func testFrageWirdNichtBeantwortet() {
        let roh = "Kannst du mir die Datei bis morgen schicken?"
        let antwort = "Ja, ich kann dir die Datei bis morgen schicken."
        XCTAssertEqual(Cleanup.validate(roh: roh, sauber: antwort), roh)
    }
}
