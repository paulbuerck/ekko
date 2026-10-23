import XCTest
@testable import Ekko

@MainActor
final class QwenCleanupTests: XCTestCase {
    func testOhneDenkblockEntferntLeerenBlock() {
        let roh = "<think>\n\n</think>\n\nHallo Welt."
        XCTAssertEqual(QwenCleanup.ohneDenkblock(roh), "Hallo Welt.")
    }

    func testOhneDenkblockEntferntGefuelltenBlock() {
        let roh = "<think>Der Nutzer will…</think>Fertig geputzt."
        XCTAssertEqual(QwenCleanup.ohneDenkblock(roh), "Fertig geputzt.")
    }

    func testOhneDenkblockLaesstNormalenTextInRuhe() {
        XCTAssertEqual(QwenCleanup.ohneDenkblock("  Nur Text.\n"), "Nur Text.")
    }

    func testEngineDefaultIstApple() {
        UserDefaults.standard.removeObject(forKey: "cleanupEngine")
        XCTAssertEqual(CleanupEngine.gespeichert, .apple)
    }

    func testEnginePersistiert() {
        let vorher = CleanupEngine.gespeichert
        defer { CleanupEngine.gespeichert = vorher }
        CleanupEngine.gespeichert = .qwen
        XCTAssertEqual(CleanupEngine.gespeichert, .qwen)
    }
}
