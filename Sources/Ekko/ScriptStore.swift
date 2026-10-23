// Sources/Ekko/ScriptStore.swift
import Foundation

/// Teleprompter-Skripte: Markdown-Dateien in ~/Diktate/Teleprompter/ —
/// sichtbar und extern editierbar, Muster wie TranscriptStore.
/// Verzeichnis injizierbar (Tests schreiben nie ins echte ~/Diktate,
/// Lehre aus dem Queue-Test-Bug).
@MainActor
final class ScriptStore: ObservableObject {
    struct Skript: Identifiable, Hashable {
        let url: URL
        let titel: String
        let datum: Date
        let wortzahl: Int
        var id: URL { url }

        /// Grobe Vorlese-Dauer; 140 WpM als Ausgangswert.
        var dauerMinuten: Double { Double(wortzahl) / 140.0 }
    }

    private let ordner: URL
    @Published private(set) var skripte: [Skript] = []

    init(ordner: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Diktate/Teleprompter")) {
        self.ordner = ordner
    }

    func lade() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let alle = (try? FileManager.default.contentsOfDirectory(
            at: ordner, includingPropertiesForKeys: keys)) ?? []
        skripte = alle
            .filter { $0.pathExtension == "md" }
            .map { url in
                let datum = (try? url.resourceValues(forKeys: Set(keys))
                    .contentModificationDate) ?? .distantPast
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return Skript(
                    url: url,
                    titel: url.deletingPathExtension().lastPathComponent,
                    datum: datum,
                    wortzahl: Self.wortzahl(text))
            }
            .sorted { $0.datum > $1.datum }
    }

    @discardableResult
    func neu(titel: String, text: String = "") throws -> Skript {
        try FileManager.default.createDirectory(
            at: ordner, withIntermediateDirectories: true)
        let basis = titel.trimmingCharacters(in: .whitespaces)
        let name = basis.isEmpty ? "Skript" : basis
        var ziel = ordner.appendingPathComponent("\(name).md")
        var lauf = 2
        while FileManager.default.fileExists(atPath: ziel.path) {
            ziel = ordner.appendingPathComponent("\(name) \(lauf).md")
            lauf += 1
        }
        try text.write(to: ziel, atomically: true, encoding: .utf8)
        lade()
        // Pfad-Vergleich mit aufgelösten Symlinks: /var/… vs /private/var/…
        let zielPfad = ziel.resolvingSymlinksInPath().path
        guard let s = skripte.first(where: {
            $0.url.resolvingSymlinksInPath().path == zielPfad
        }) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return s
    }

    func inhalt(_ s: Skript) -> String {
        (try? String(contentsOf: s.url, encoding: .utf8)) ?? ""
    }

    func speichere(_ s: Skript, text: String) throws {
        try text.write(to: s.url, atomically: true, encoding: .utf8)
        lade()
    }

    func benenneUm(_ s: Skript, zu titel: String) throws {
        let sauber = titel.trimmingCharacters(in: .whitespaces)
        guard !sauber.isEmpty else { return }
        let ziel = ordner.appendingPathComponent("\(sauber).md")
        try FileManager.default.moveItem(at: s.url, to: ziel)
        lade()
    }

    func loesche(_ s: Skript) throws {
        try FileManager.default.removeItem(at: s.url)
        lade()
    }

    static func wortzahl(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
