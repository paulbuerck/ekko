import Foundation

/// Ein erkanntes Segment aus dem Streaming-Pass — bewusst ohne
/// WhisperKit-Typ, damit die Confirm-Logik pur testbar bleibt.
struct LiveSegment: Equatable, Sendable {
    let text: String
    /// Absolutes Ende in Sekunden (WhisperKit behält die Zeitachse
    /// über clipTimestamps hinweg bei — gemessen).
    let ende: Float
}

/// Confirm-Logik des Live-Diktats, Muster wie WhisperKits
/// AudioStreamTranscriber: die letzten `fenster` Segmente eines Passes
/// bleiben Hypothese (können sich noch ändern), alles davor wird fest.
/// Bestätigtes wächst nur vorwärts — kein Zappeln, keine Duplikate.
struct LiveKonfirmation: Sendable {
    private(set) var bestaetigte: [LiveSegment] = []
    private(set) var hypothese: [LiveSegment] = []
    private(set) var bestaetigtEnde: Float = 0
    let fenster: Int

    init(fenster: Int = 2) {
        self.fenster = fenster
    }

    /// Ergebnis eines Streaming-Passes einarbeiten (Segmente ab
    /// clipTimestamp = bestaetigtEnde des vorigen Standes).
    mutating func nimm(_ segmente: [LiveSegment]) {
        guard segmente.count > fenster else {
            hypothese = segmente
            return
        }
        let neu = segmente.prefix(segmente.count - fenster)
        if let ende = neu.last?.ende, ende > bestaetigtEnde {
            bestaetigtEnde = ende
            bestaetigte.append(contentsOf:
                neu.filter { $0.ende > (bestaetigte.last?.ende ?? -1) })
        }
        hypothese = Array(segmente.suffix(fenster))
    }

    /// Loslassen: letzter Pass bestätigt alles. Liefert der Pass nichts
    /// (z. B. nur Stille seit letzter Konfirmation), zählt die stehende
    /// Hypothese als Ergebnis.
    mutating func schliesseAb(mit segmente: [LiveSegment]) {
        let rest = segmente.filter { $0.ende > bestaetigtEnde }
        bestaetigte.append(contentsOf: rest.isEmpty ? hypothese : rest)
        hypothese = []
        if let ende = bestaetigte.last?.ende {
            bestaetigtEnde = ende
        }
    }

    var bestaetigterText: String { text(bestaetigte) }
    var hypothesenText: String { text(hypothese) }

    private func text(_ segmente: [LiveSegment]) -> String {
        segmente.map {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
