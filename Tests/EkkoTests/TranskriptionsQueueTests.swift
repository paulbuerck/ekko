import XCTest
@testable import Ekko

@MainActor
final class TranskriptionsQueueTests: XCTestCase {
    private var ablageVorher: URL!
    private var tempAblage: URL!

    override func setUp() async throws {
        // nie ins echte ~/Diktate schreiben (Mock-Transkripte landeten dort)
        ablageVorher = TranskriptAblage.verzeichnis
        tempAblage = FileManager.default.temporaryDirectory
            .appendingPathComponent("ekko-test-ablage-\(UUID().uuidString)")
        TranskriptAblage.verzeichnis = tempAblage
    }

    override func tearDown() async throws {
        TranskriptAblage.verzeichnis = ablageVorher
        try? FileManager.default.removeItem(at: tempAblage)
    }

    struct MockOK: Transkribierer {
        func transkribiere(_ audio: URL) async throws -> String { "hallo welt" }
    }
    struct MockFehler: Transkribierer {
        struct E: Error {}
        func transkribiere(_ audio: URL) async throws -> String { throw E() }
    }

    private func tempAudio() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        try Data([0]).write(to: url)
        return url
    }

    func testErfolgFuehrtZuFertig() async throws {
        let q = TranskriptionsQueue(
            transkribierer: MockOK(), woerterbuch: Woerterbuch(),
            aufTranskript: { _, _ in })
        q.fuegeDateiHinzu(try tempAudio())
        await q.verarbeiteNaechstes()
        guard case .fertig = q.items[0].zustand else {
            return XCTFail("erwartet .fertig, ist \(q.items[0].zustand)") }
    }

    func testFehlerFuehrtZuFehlerZustand() async throws {
        let q = TranskriptionsQueue(
            transkribierer: MockFehler(), woerterbuch: Woerterbuch(),
            aufTranskript: { _, _ in })
        q.fuegeDateiHinzu(try tempAudio())
        await q.verarbeiteNaechstes()
        guard case .fehler = q.items[0].zustand else {
            return XCTFail("erwartet .fehler") }
    }

    func testMehrereItemsWerdenAlleVerarbeitet() async throws {
        let q = TranskriptionsQueue(
            transkribierer: MockOK(), woerterbuch: Woerterbuch(),
            aufTranskript: { _, _ in })
        q.fuegeDateiHinzu(try tempAudio())
        q.fuegeDateiHinzu(try tempAudio())
        await q.verarbeiteNaechstes()
        guard case .fertig = q.items[0].zustand else {
            return XCTFail("item0 erwartet .fertig, ist \(q.items[0].zustand)") }
        guard case .fertig = q.items[1].zustand else {
            return XCTFail("item1 erwartet .fertig, ist \(q.items[1].zustand)") }
    }

    func testPausiertStartetNichts() async throws {
        let q = TranskriptionsQueue(
            transkribierer: MockOK(), woerterbuch: Woerterbuch(),
            aufTranskript: { _, _ in })
        q.pausiert = true
        q.fuegeDateiHinzu(try tempAudio())
        await q.verarbeiteNaechstes()
        XCTAssertEqual(q.items[0].zustand, .wartet)
    }
}
