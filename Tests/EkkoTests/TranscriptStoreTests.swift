// Tests/EkkoTests/TranscriptStoreTests.swift
import XCTest
@testable import Ekko

@MainActor
final class TranscriptStoreTests: XCTestCase {
    private func tempStore(_ dateien: [String: String]) throws
        -> (TranscriptStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        for (name, inhalt) in dateien {
            try inhalt.write(
                to: dir.appendingPathComponent(name),
                atomically: true, encoding: .utf8)
        }
        return (TranscriptStore(ordner: dir), dir)
    }

    func testListetNurMarkdownNeuesteZuerst() throws {
        let (store, _) = try tempStore([
            "a-transkript.md": "# a", "b.txt": "kein md",
            "c-meeting.md": "# c"])
        store.lade()
        XCTAssertEqual(store.transkripte.count, 2)
        XCTAssertTrue(store.transkripte.contains { $0.istMeeting })
    }

    func testBenenntUm() throws {
        let (store, dir) = try tempStore(["alt-transkript.md": "# x"])
        store.lade()
        try store.benenneUm(store.transkripte[0], zu: "neu")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("neu.md").path))
    }

    func testLoescht() throws {
        let (store, dir) = try tempStore(["weg-transkript.md": "# x"])
        store.lade()
        try store.loesche(store.transkripte[0])
        XCTAssertEqual(store.transkripte.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("weg-transkript.md").path))
    }
}
