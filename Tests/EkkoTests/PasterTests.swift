import AppKit
import XCTest
@testable import Ekko

/// Wiederherstellung erst nach Abruf durch die Ziel-App, nicht nach
/// fixer Wartezeit. Private Pasteboards statt .general — Tests dürfen
/// die echte Zwischenablage nicht anfassen.
@MainActor
final class PasterTests: XCTestCase {
    private var pb: NSPasteboard!

    override func setUp() async throws {
        pb = NSPasteboard(name: .init("ekko-test-\(UUID().uuidString)"))
        pb.clearContents()
        pb.setString("alt", forType: .string)
    }

    override func tearDown() async throws {
        pb.releaseGlobally()
    }

    func testAbgeholtDannAlterInhaltZurueck() {
        let fertig = expectation(description: "fertig")
        var gelesen: String?
        var ergebnis: Paster.Ergebnis?
        Paster.paste("neu", auf: pb, timeout: 2,
                     sendeEinfuegen: { gelesen = self.pb.string(forType: .string) },
                     fertig: { ergebnis = $0; fertig.fulfill() })
        wait(for: [fertig], timeout: 3)
        XCTAssertEqual(gelesen, "neu")
        XCTAssertEqual(ergebnis, .eingefuegt)
        XCTAssertEqual(pb.string(forType: .string), "alt")
    }

    func testNichtAbgeholtDiktatBleibtLiegen() {
        let fertig = expectation(description: "fertig")
        var ergebnis: Paster.Ergebnis?
        Paster.paste("neu", auf: pb, timeout: 0.2,
                     sendeEinfuegen: {},
                     fertig: { ergebnis = $0; fertig.fulfill() })
        wait(for: [fertig], timeout: 3)
        XCTAssertEqual(ergebnis, .nichtAbgeholt)
        XCTAssertEqual(pb.string(forType: .string), "neu")
    }

    func testFremdeAenderungWirdNichtUeberschrieben() {
        let fertig = expectation(description: "fertig")
        Paster.paste("neu", auf: pb, timeout: 2,
                     sendeEinfuegen: {
                         _ = self.pb.string(forType: .string)
                         // Nutzer kopiert sofort etwas anderes:
                         self.pb.clearContents()
                         self.pb.setString("fremd", forType: .string)
                     },
                     fertig: { _ in fertig.fulfill() })
        wait(for: [fertig], timeout: 3)
        XCTAssertEqual(pb.string(forType: .string), "fremd")
    }

    /// Alle Typen sichern, nicht nur Text —
    /// sonst gehen kopierte Bilder/RTF beim Diktieren verloren.
    func testAlleTypenKommenZurueck() {
        let rtf = Data("{\\rtf1 alt}".utf8)
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString("alt", forType: .string)
        item.setData(rtf, forType: .rtf)
        item.setData(png, forType: .png)
        pb.writeObjects([item])

        let fertig = expectation(description: "fertig")
        Paster.paste("neu", auf: pb, timeout: 2,
                     sendeEinfuegen: { _ = self.pb.string(forType: .string) },
                     fertig: { _ in fertig.fulfill() })
        wait(for: [fertig], timeout: 3)
        XCTAssertEqual(pb.string(forType: .string), "alt")
        XCTAssertEqual(pb.data(forType: .rtf), rtf)
        XCTAssertEqual(pb.data(forType: .png), png)
    }

    func testMehrereEintraegeKommenZurueck() {
        pb.clearContents()
        let a = NSPasteboardItem(); a.setString("eins", forType: .string)
        let b = NSPasteboardItem(); b.setString("zwei", forType: .string)
        pb.writeObjects([a, b])

        let fertig = expectation(description: "fertig")
        Paster.paste("neu", auf: pb, timeout: 2,
                     sendeEinfuegen: { _ = self.pb.string(forType: .string) },
                     fertig: { _ in fertig.fulfill() })
        wait(for: [fertig], timeout: 3)
        XCTAssertEqual(pb.pasteboardItems?.compactMap { $0.string(forType: .string) },
                       ["eins", "zwei"])
    }

    func testLeereZwischenablageBleibtLeer() {
        pb.clearContents()
        let fertig = expectation(description: "fertig")
        Paster.paste("neu", auf: pb, timeout: 2,
                     sendeEinfuegen: { _ = self.pb.string(forType: .string) },
                     fertig: { _ in fertig.fulfill() })
        wait(for: [fertig], timeout: 3)
        XCTAssertNil(pb.string(forType: .string))
    }

    /// Live-Befund 2026-10-22: Notizen fügte den ALTEN Inhalt ein, weil
    /// sofort nach der ersten Anfrage zurückgeschrieben wurde. Nach dem
    /// Paste muss der Text 500 ms liegen bleiben.
    func testTextBleibtWaehrendNachlauf() {
        let fertig = expectation(description: "fertig")
        var spaeterGelesen: String?
        Paster.paste("neu", auf: pb, timeout: 2, nachlauf: 0.3,
                     sendeEinfuegen: {
                         _ = self.pb.string(forType: .string)
                         DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                             spaeterGelesen = self.pb.string(forType: .string)
                         }
                     },
                     fertig: { _ in fertig.fulfill() })
        wait(for: [fertig], timeout: 3)
        XCTAssertEqual(spaeterGelesen, "neu")
        XCTAssertEqual(pb.string(forType: .string), "alt")
    }

    /// Abholung kurz vor dem Timeout: der Timeout darf das laufende
    /// Einfügen nicht als gescheitert werten.
    func testTimeoutWaehrendNachlaufZaehltAlsEingefuegt() {
        let fertig = expectation(description: "fertig")
        var ergebnis: Paster.Ergebnis?
        Paster.paste("neu", auf: pb, timeout: 0.1, nachlauf: 0.3,
                     sendeEinfuegen: { _ = self.pb.string(forType: .string) },
                     fertig: { ergebnis = $0; fertig.fulfill() })
        wait(for: [fertig], timeout: 3)
        XCTAssertEqual(ergebnis, .eingefuegt)
        XCTAssertEqual(pb.string(forType: .string), "alt")
    }

    func testTransientMarkerGesetzt() {
        Paster.paste("neu", auf: pb, timeout: 0.2,
                     sendeEinfuegen: {}, fertig: nil)
        XCTAssertTrue(pb.types?.contains(Paster.transientTyp) ?? false)
    }
}
