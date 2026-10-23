import XCTest
@testable import Ekko

@MainActor
final class ScriptStoreTests: XCTestCase {
    var ordner: URL!
    var store: ScriptStore!

    override func setUp() async throws {
        ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent("ekko-scripts-\(UUID().uuidString)")
        store = ScriptStore(ordner: ordner)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: ordner)
    }

    func testNeuLegtDateiAn() throws {
        let s = try store.neu(titel: "Pitch", text: "Guten Tag zusammen.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.url.path))
        XCTAssertEqual(store.skripte.count, 1)
        XCTAssertEqual(store.inhalt(s), "Guten Tag zusammen.")
    }

    func testSpeichernUeberschreibt() throws {
        let s = try store.neu(titel: "Pitch", text: "Alt.")
        try store.speichere(s, text: "Neu und länger.")
        XCTAssertEqual(store.inhalt(s), "Neu und länger.")
    }

    func testWortzahlUndDauer() throws {
        let text = Array(repeating: "wort", count: 280).joined(separator: " ")
        let s = try store.neu(titel: "Lang", text: text)
        XCTAssertEqual(s.wortzahl, 280)
        // 280 Wörter / 140 WpM = 2 min
        XCTAssertEqual(s.dauerMinuten, 2.0, accuracy: 0.01)
    }

    func testUmbenennen() throws {
        let s = try store.neu(titel: "Alt", text: "x")
        try store.benenneUm(s, zu: "Neu")
        XCTAssertEqual(store.skripte.first?.titel, "Neu")
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.url.path))
    }

    func testLoeschen() throws {
        let s = try store.neu(titel: "Weg", text: "x")
        try store.loesche(s)
        XCTAssertTrue(store.skripte.isEmpty)
    }

    func testTitelKollisionBekommtSuffix() throws {
        _ = try store.neu(titel: "Pitch", text: "eins")
        let zwei = try store.neu(titel: "Pitch", text: "zwei")
        XCTAssertEqual(store.skripte.count, 2)
        XCTAssertNotEqual(zwei.titel, "Pitch")
    }

    func testKeineDateienAusserhalbDesOrdners() throws {
        _ = try store.neu(titel: "Pitch", text: "x")
        let inhalt = try FileManager.default.contentsOfDirectory(
            at: ordner, includingPropertiesForKeys: nil)
        XCTAssertEqual(inhalt.count, 1)  // genau die eine .md
    }
}
