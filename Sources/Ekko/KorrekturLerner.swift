import Foundation

/// Lernt Wörterbuch-Regeln aus der Nachbesserung im Zielfeld.
/// Vergleicht den eingefügten Text mit
/// dem späteren Feldinhalt und nimmt nur eindeutige Fälle: 1–2 Wörter,
/// ersetzt durch 1–2 ähnliche Wörter zwischen unveränderten Nachbarn.
/// Alles andere (Umformulieren, Ergänzen, Inhaltsänderung) lernt nichts.
enum KorrekturLerner {
    struct Regel: Equatable { let falsch: String; let richtig: String }

    /// Mindestähnlichkeit (1 − Editierdistanz/Länge) zwischen Fassungen.
    static let mindestAehnlichkeit = 0.5
    /// Anteil des eingefügten Texts, der im Feld wiederzufinden sein muss.
    static let mindestAbdeckung = 0.5

    static func vorschlaege(eingefuegt: String, feldtext: String,
                            bekannt: Set<String> = []) -> [Regel] {
        let p = woerter(eingefuegt)
        let f = Array(woerter(feldtext).prefix(4000))
        guard !p.isEmpty, !f.isEmpty else { return [] }

        let paare = lcs(p, f)
        guard Double(paare.count) / Double(p.count) >= mindestAbdeckung
        else { return [] }

        var regeln: [Regel] = []
        func pruefe(_ alt: ArraySlice<String>, _ neu: ArraySlice<String>) {
            guard (1...2).contains(alt.count), (1...2).contains(neu.count)
            else { return }
            let falsch = alt.joined(separator: " ")
            let richtig = neu.joined(separator: " ")
            guard istErkennungsfehler(falsch, richtig),
                  !bekannt.contains(falsch.lowercased()),
                  !regeln.contains(where: { $0.falsch == falsch })
            else { return }
            regeln.append(Regel(falsch: falsch, richtig: richtig))
        }

        // Lücken zwischen aufeinanderfolgenden Treffern.
        for (a, b) in zip(paare, paare.dropFirst()) {
            pruefe(p[(a.0 + 1)..<b.0], f[(a.1 + 1)..<b.1])
        }
        // Ränder: nur gleich viele Wörter direkt neben dem Anker — davor
        // bzw. dahinter steht im Feld oft anderer Text.
        if let erstes = paare.first, erstes.0 > 0, erstes.1 >= erstes.0 {
            pruefe(p[0..<erstes.0], f[(erstes.1 - erstes.0)..<erstes.1])
        }
        if let letztes = paare.last {
            let rest = p.count - 1 - letztes.0
            if rest > 0, f.count - 1 - letztes.1 >= rest {
                pruefe(p[(letztes.0 + 1)...],
                       f[(letztes.1 + 1)...(letztes.1 + rest)])
            }
        }
        return regeln
    }

    /// Wörter ohne anhängende Interpunktion.
    static func woerter(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).compactMap { roh in
            let kern = roh.trimmingCharacters(in: .punctuationCharacters
                .union(.symbols))
            return kern.isEmpty ? nil : kern
        }
    }

    /// Ähnlich genug für einen Hör-/Schreibfehler, aber kein Wortanbau
    /// („morgen" → „übermorgen" ist Inhalt, nicht Erkennung).
    static func istErkennungsfehler(_ falsch: String, _ richtig: String) -> Bool {
        let a = normal(falsch), b = normal(richtig)
        guard a.count >= 3, falsch != richtig else { return false }
        if a == b { return true }  // nur Groß/Klein oder Leerzeichen
        if a.contains(b) || b.contains(a) { return false }
        let distanz = levenshtein(Array(a), Array(b))
        return 1 - Double(distanz) / Double(max(a.count, b.count))
            >= mindestAehnlichkeit
    }

    private static func normal(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Längste gemeinsame Teilfolge als Index-Paare (p, f).
    private static func lcs(_ p: [String], _ f: [String]) -> [(Int, Int)] {
        let n = p.count, m = f.count
        var t = Array(repeating: Array(repeating: 0, count: m + 1),
                      count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                t[i][j] = p[i] == f[j]
                    ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
            }
        }
        var paare: [(Int, Int)] = []
        var i = 0, j = 0
        while i < n, j < m {
            if p[i] == f[j] { paare.append((i, j)); i += 1; j += 1 }
            else if t[i + 1][j] >= t[i][j + 1] { i += 1 } else { j += 1 }
        }
        return paare
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var vorher = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var aktuell = [i + 1]
            for (j, cb) in b.enumerated() {
                aktuell.append(min(vorher[j + 1] + 1, aktuell[j] + 1,
                                   vorher[j] + (ca == cb ? 0 : 1)))
            }
            vorher = aktuell
        }
        return vorher[b.count]
    }
}
