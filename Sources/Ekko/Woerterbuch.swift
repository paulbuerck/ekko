import Foundation

/// Ersetzungs-Wörterbuch: ~/Diktate/woerterbuch.txt,
/// Zeilen `falsch -> richtig`, `#` Kommentar. Hot-Reload per mtime,
/// Wortgrenzen, case-insensitiv; fehlende/kaputte Datei = no-op.
@MainActor
final class Woerterbuch {
    private let pfad: URL
    init(pfad: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Diktate/woerterbuch.txt")) {
        self.pfad = pfad
    }
    private var cacheMtime: Date?
    private var regeln: [(NSRegularExpression, String)] = []

    func apply(_ text: String) -> String {
        guard let mtime = try? FileManager.default
            .attributesOfItem(atPath: pfad.path)[.modificationDate] as? Date
        else { return text }
        if mtime != cacheMtime {
            lade()
            cacheMtime = mtime
        }
        var result = text
        for (regex, richtig) in regeln {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: richtig)
        }
        return result
    }

    private func lade() {
        regeln = []
        guard let inhalt = try? String(contentsOf: pfad, encoding: .utf8)
        else { return }
        for zeile in inhalt.split(separator: "\n") {
            let z = zeile.trimmingCharacters(in: .whitespaces)
            if z.isEmpty || z.hasPrefix("#") || !z.contains("->") { continue }
            let teile = z.split(separator: "->", maxSplits: 1)
            guard teile.count == 2 else { continue }
            let falsch = teile[0].trimmingCharacters(in: .whitespaces)
            let richtig = teile[1].trimmingCharacters(in: .whitespaces)
            guard !falsch.isEmpty, !richtig.isEmpty,
                  let regex = try? NSRegularExpression(
                      pattern: "\\b\(NSRegularExpression.escapedPattern(for: falsch))\\b",
                      options: [.caseInsensitive])
            else { continue }
            regeln.append((regex, NSRegularExpression
                .escapedTemplate(for: richtig)))
        }
    }
}
