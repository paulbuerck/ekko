import XCTest
@testable import Ekko

/// Dauerhafte Statistik: nur Zahlen pro Tag, nie Text.
final class StatistikTests: XCTestCase {
    private let kal = Calendar(identifier: .gregorian)
    private func tag(_ s: String, _ stunde: Int = 12) -> Date {
        let t = s.split(separator: "-").map { Int($0)! }
        return kal.date(from: DateComponents(
            year: t[0], month: t[1], day: t[2], hour: stunde))!
    }

    func testSummiertProTag() {
        var s = Statistik()
        s.erfasse(woerter: 10, dauer: 1.0, am: tag("2026-10-20", 9), kalender: kal)
        s.erfasse(woerter: 5, dauer: 3.0, am: tag("2026-10-20", 18), kalender: kal)
        s.erfasse(woerter: 7, dauer: 2.0, am: tag("2026-10-21"), kalender: kal)
        XCTAssertEqual(s.woerterGesamt, 22)
        XCTAssertEqual(s.diktate(am: tag("2026-10-20"), kalender: kal), 2)
        XCTAssertEqual(s.diktate(am: tag("2026-10-22"), kalender: kal), 0)
    }

    func testDurchschnittlicheLatenzNurImZeitraum() {
        var s = Statistik()
        s.erfasse(woerter: 1, dauer: 9.0, am: tag("2026-08-01"), kalender: kal)
        s.erfasse(woerter: 1, dauer: 1.0, am: tag("2026-10-20"), kalender: kal)
        s.erfasse(woerter: 1, dauer: 2.0, am: tag("2026-10-21"), kalender: kal)
        let mittel = s.mittlereLatenz(tage: 30, bis: tag("2026-10-22"), kalender: kal)
        XCTAssertEqual(mittel ?? 0, 1.5, accuracy: 0.001)
        XCTAssertNil(Statistik().mittlereLatenz(tage: 30, bis: Date(), kalender: kal))
    }

    func testStreakZaehltBisHeute() {
        var s = Statistik()
        for d in ["2026-10-18", "2026-10-20", "2026-10-21", "2026-10-22"] {
            s.erfasse(woerter: 1, dauer: 1, am: tag(d), kalender: kal)
        }
        XCTAssertEqual(s.streak(bis: tag("2026-10-22"), kalender: kal), 3)
    }

    func testStreakHaeltBisGesternOhneDiktatHeute() {
        var s = Statistik()
        for d in ["2026-10-20", "2026-10-21"] {
            s.erfasse(woerter: 1, dauer: 1, am: tag(d), kalender: kal)
        }
        // Heute noch nichts diktiert: Serie ist noch nicht gerissen.
        XCTAssertEqual(s.streak(bis: tag("2026-10-22"), kalender: kal), 2)
        // Ein ganzer Tag Pause: Serie gerissen.
        XCTAssertEqual(s.streak(bis: tag("2026-10-23"), kalender: kal), 0)
    }

    /// Bis 2026-10-23 wurde die Latenz ab Tastendruck gemessen (Sprechzeit
    /// inklusive). Alte Dateien: Wörter/Diktate behalten, Latenz verwerfen.
    func testAlteLatenzWirdIgnoriert() throws {
        let alt = #"{"tage":{"2026-10-23":{"diktate":3,"woerter":29,"latenzSumme":27.0}}}"#
        let s = try JSONDecoder().decode(Statistik.self, from: Data(alt.utf8))
        XCTAssertEqual(s.woerterGesamt, 29)
        XCTAssertEqual(s.diktate(am: tag("2026-10-23"), kalender: kal), 3)
        XCTAssertNil(s.mittlereLatenz(tage: 30, bis: tag("2026-10-23"), kalender: kal))
    }

    func testSpeichernUndLaden() throws {
        let datei = FileManager.default.temporaryDirectory
            .appendingPathComponent("ekko-stat-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: datei) }
        var s = Statistik()
        s.erfasse(woerter: 12, dauer: 0.8, am: tag("2026-10-21"), kalender: kal)
        try s.speichere(nach: datei)
        let geladen = Statistik.lade(von: datei)
        XCTAssertEqual(geladen, s)
        XCTAssertEqual(Statistik.lade(von: datei.appendingPathExtension("fehlt")),
                       Statistik())
    }
}
