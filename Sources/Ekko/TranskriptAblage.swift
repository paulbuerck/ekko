import Foundation

/// Legt Datei-Transkripte als Markdown in ~/Diktate/ ab
/// (gleicher Ort wie die Meeting-Transkripte).
enum TranskriptAblage {
    /// Tests überschreiben das Verzeichnis (sonst schrieben Queue-Tests
    /// ihre Mock-Transkripte ins echte ~/Diktate — Befund 2026-07-09).
    nonisolated(unsafe) static var verzeichnis =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Diktate")

    /// `anzeigeName` (z.B. der Video-Titel eines Web-Imports) benennt Datei
    /// und Überschrift; ohne ihn greift der Dateiname der Quelle
    /// (bei Web-URLs sonst nur die kryptische Video-ID).
    static func schreibe(quelle: URL, text: String,
                         anzeigeName: String? = nil) throws -> URL {
        let dir = verzeichnis
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let titel = anzeigeName?.trimmingCharacters(in: .whitespaces)
        let basis = titel.map(dateiName) ?? quelle.deletingPathExtension()
            .lastPathComponent
        let ueberschrift = (titel?.isEmpty == false ? titel! : quelle.lastPathComponent)
        var ziel = dir.appendingPathComponent("\(basis)-transkript.md")
        var n = 2
        while FileManager.default.fileExists(atPath: ziel.path) {
            ziel = dir.appendingPathComponent("\(basis)-transkript-\(n).md")
            n += 1
        }
        let inhalt = """
        # Transkript: \(ueberschrift)

        Quelle: \(quelle.path)
        Erstellt: \(ISO8601DateFormatter().string(from: Date())) (Ekko)

        ---

        \(text)
        """
        try inhalt.write(to: ziel, atomically: true, encoding: .utf8)
        return ziel
    }

    /// Titel → dateisicherer Basisname: Pfad-/Sonderzeichen zu „-",
    /// Whitespace zusammengefasst, auf 80 Zeichen gekappt.
    static func dateiName(_ titel: String) -> String {
        let verboten = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.controlCharacters).union(.newlines)
        let bereinigt = titel.components(separatedBy: verboten)
            .joined(separator: "-")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let gekappt = String(bereinigt.prefix(80))
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        return gekappt.isEmpty ? "transkript" : gekappt
    }
}
