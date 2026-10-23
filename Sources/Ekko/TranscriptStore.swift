// Sources/Ekko/TranscriptStore.swift
import Foundation

@MainActor
final class TranscriptStore: ObservableObject {
    struct Transkript: Identifiable, Hashable {
        let url: URL
        let name: String
        let datum: Date
        let istMeeting: Bool
        var id: URL { url }
    }

    private let ordner: URL
    @Published private(set) var transkripte: [Transkript] = []

    init(ordner: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Diktate")) {
        self.ordner = ordner
    }

    func lade() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let alle = (try? FileManager.default.contentsOfDirectory(
            at: ordner, includingPropertiesForKeys: keys)) ?? []
        transkripte = alle
            .filter { $0.pathExtension == "md" }
            .map { url in
                let datum = (try? url.resourceValues(forKeys: Set(keys))
                    .contentModificationDate) ?? .distantPast
                let name = url.deletingPathExtension().lastPathComponent
                return Transkript(
                    url: url, name: name, datum: datum,
                    istMeeting: name.contains("meeting"))
            }
            .sorted { $0.datum > $1.datum }
    }

    func inhalt(_ t: Transkript) -> String {
        (try? String(contentsOf: t.url, encoding: .utf8)) ?? ""
    }

    func benenneUm(_ t: Transkript, zu name: String) throws {
        let sauber = name.trimmingCharacters(in: .whitespaces)
        guard !sauber.isEmpty else { return }
        let ziel = ordner.appendingPathComponent("\(sauber).md")
        try FileManager.default.moveItem(at: t.url, to: ziel)
        lade()
    }

    func loesche(_ t: Transkript) throws {
        try FileManager.default.removeItem(at: t.url)
        lade()
    }
}
