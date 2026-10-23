import Foundation

/// Wort-Tracking des Teleprompters: matcht die (wachsende, revidierbare)
/// STT-Hypothese gegen das Skript und hält die Position des nächsten zu
/// sprechenden Worts. Pur und ohne UI/Audio testbar.
///
/// Regeln:
/// - Vorwärts-Suchfenster ab aktueller Position, kein Rückwärtssprung.
/// - Ad-lib/Versprecher → kein Match → Position hält (Text wartet).
/// - Sprung über >2 Skriptwörter nur, wenn das FOLGENDE gesprochene Wort
///   den Anschluss bestätigt — sonst wäre ein zufälliges Skriptwort im
///   Ad-lib („… heute übrigens …") ein Fehlsprung.
struct Aligner: Sendable {
    /// Original-Wörter des Skripts (für die Anzeige, Reihenfolge = Index).
    let woerter: [String]
    private let tokens: [String]
    private let fenster: Int
    private(set) var position: Int = 0

    init(skript: String, fenster: Int = 12) {
        woerter = skript.split(whereSeparator: \.isWhitespace)
            .map(String.init)
        tokens = woerter.map { Self.normalisiere($0) }
        self.fenster = fenster
    }

    /// Kompletten bisherigen Hypothese-Text einarbeiten. Immer der volle
    /// Text (nicht Deltas) — STT revidiert; Rückschritte fängt das
    /// `max()` am Ende ab.
    mutating func hoere(_ gesprochen: String) {
        let g = gesprochen.lowercased()
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
        var pos = 0
        for (i, wort) in g.enumerated() {
            let ende = min(pos + fenster, tokens.count)
            guard pos < ende,
                  let idx = tokens[pos..<ende].firstIndex(of: wort)
            else { continue }
            let sprung = idx - pos
            if sprung <= 2 {
                pos = idx + 1
            } else if i + 1 < g.count, idx + 1 < tokens.count,
                      g[i + 1] == tokens[idx + 1] {
                pos = idx + 1
            }
            // sonst: unbestätigter Fernsprung — vermutlich Ad-lib.
        }
        position = max(position, pos)
    }

    /// Klick aufs Wort im Prompter: Position manuell setzen (einziger
    /// erlaubter Rückwärtsweg).
    mutating func setzePosition(_ neu: Int) {
        position = min(max(0, neu), tokens.count)
    }

    var fortschritt: Double {
        tokens.isEmpty ? 0 : Double(position) / Double(tokens.count)
    }

    private static func normalisiere(_ wort: String) -> String {
        String(wort.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
