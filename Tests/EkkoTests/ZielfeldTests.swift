import XCTest
@testable import Ekko

/// Einfüge-Entscheid vor ⌘V. Nur blockieren, wenn AX es sicher weiß —
/// weiß AX nichts (Electron ohne AX-Baum), wird wie bisher eingefügt.
final class ZielfeldTests: XCTestCase {
    func testTextRollenSindEditierbar() {
        XCTAssertEqual(Zielfeld.feldart(rolle: "AXTextField", subrolle: nil, wertSetzbar: false), .editierbar)
        XCTAssertEqual(Zielfeld.feldart(rolle: "AXTextArea", subrolle: nil, wertSetzbar: nil), .editierbar)
        XCTAssertEqual(Zielfeld.feldart(rolle: "AXComboBox", subrolle: nil, wertSetzbar: nil), .editierbar)
    }

    func testSetzbarerWertIstEditierbar() {
        XCTAssertEqual(Zielfeld.feldart(rolle: "AXGroup", subrolle: nil, wertSetzbar: true), .editierbar)
    }

    func testPasswortfeld() {
        XCTAssertEqual(Zielfeld.feldart(rolle: "AXTextField", subrolle: "AXSecureTextField", wertSetzbar: true), .passwort)
    }

    func testEindeutigKeinTextfeld() {
        for rolle in ["AXButton", "AXStaticText", "AXImage", "AXCheckBox", "AXLink"] {
            XCTAssertEqual(Zielfeld.feldart(rolle: rolle, subrolle: nil, wertSetzbar: false), .keinTextfeld, rolle)
        }
    }

    func testContainerUndUnbekanntBleibenUnbekannt() {
        // Electron/Web liefern oft nur Container — dort darf nicht blockiert werden.
        XCTAssertEqual(Zielfeld.feldart(rolle: "AXWebArea", subrolle: nil, wertSetzbar: false), .unbekannt)
        XCTAssertEqual(Zielfeld.feldart(rolle: "AXGroup", subrolle: nil, wertSetzbar: nil), .unbekannt)
        XCTAssertEqual(Zielfeld.feldart(rolle: nil, subrolle: nil, wertSetzbar: nil), .unbekannt)
    }

    func testEntscheidung() {
        XCTAssertEqual(Zielfeld.entscheide(feld: .editierbar, zielAppVorn: true), .einfuegen)
        XCTAssertEqual(Zielfeld.entscheide(feld: .unbekannt, zielAppVorn: true), .einfuegen)
        XCTAssertEqual(Zielfeld.entscheide(feld: .keinTextfeld, zielAppVorn: true), .nurZwischenablage(.keinTextfeld))
        XCTAssertEqual(Zielfeld.entscheide(feld: .passwort, zielAppVorn: true), .nurZwischenablage(.passwortfeld))
        XCTAssertEqual(Zielfeld.entscheide(feld: .editierbar, zielAppVorn: false), .nurZwischenablage(.appGewechselt))
    }
}
