import Foundation

/// Dauerhafte Diktat-Statistik — nur Zahlen pro Tag, nie Text oder Apps
/// (Datenschutz: Diktat-Text bleibt im RAM, nur Zahlen werden gespeichert).
/// Liegt als JSON in ~/Library/Application Support/Ekko/statistik.json.
struct Statistik: Codable, Equatable {
    struct Tag: Codable, Equatable {
        var diktate = 0
        var woerter = 0
        /// Sekunden vom Loslassen bis Text, summiert. Eigene Schlüssel:
        /// das alte `latenzSumme` (bis 2026-10-23) maß ab Tastendruck,
        /// also inkl. Sprechzeit — wird beim Laden bewusst ignoriert.
        var latenzSekunden: Double = 0
        var latenzMessungen = 0

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            diktate = try c.decodeIfPresent(Int.self, forKey: .diktate) ?? 0
            woerter = try c.decodeIfPresent(Int.self, forKey: .woerter) ?? 0
            latenzSekunden = try c.decodeIfPresent(Double.self, forKey: .latenzSekunden) ?? 0
            latenzMessungen = try c.decodeIfPresent(Int.self, forKey: .latenzMessungen) ?? 0
        }
    }

    /// Schlüssel "yyyy-MM-dd" (lokaler Kalendertag).
    var tage: [String: Tag] = [:]

    static let standardDatei = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Ekko/statistik.json")

    mutating func erfasse(woerter: Int, dauer: TimeInterval, am datum: Date = Date(),
                          kalender: Calendar = .current) {
        let k = Self.schluessel(datum, kalender)
        var t = tage[k] ?? Tag()
        t.diktate += 1
        t.woerter += woerter
        t.latenzSekunden += dauer
        t.latenzMessungen += 1
        tage[k] = t
    }

    var woerterGesamt: Int { tage.values.reduce(0) { $0 + $1.woerter } }

    func diktate(am datum: Date = Date(), kalender: Calendar = .current) -> Int {
        tage[Self.schluessel(datum, kalender)]?.diktate ?? 0
    }

    /// Ø Sekunden vom Loslassen bis zum Text über die letzten `tage`.
    func mittlereLatenz(tage anzahl: Int, bis datum: Date = Date(),
                        kalender: Calendar = .current) -> Double? {
        var summe = 0.0, n = 0
        for versatz in 0..<anzahl {
            guard let d = kalender.date(byAdding: .day, value: -versatz, to: datum),
                  let t = tage[Self.schluessel(d, kalender)] else { continue }
            summe += t.latenzSekunden
            n += t.latenzMessungen
        }
        return n > 0 ? summe / Double(n) : nil
    }

    /// Tage in Folge mit mindestens einem Diktat. Heute ohne Diktat
    /// zählt noch nicht als Abbruch (Serie läuft bis gestern weiter).
    func streak(bis datum: Date = Date(), kalender: Calendar = .current) -> Int {
        var tag = datum
        if tage[Self.schluessel(tag, kalender)] == nil {
            tag = kalender.date(byAdding: .day, value: -1, to: tag)!
        }
        var n = 0
        while tage[Self.schluessel(tag, kalender)] != nil {
            n += 1
            tag = kalender.date(byAdding: .day, value: -1, to: tag)!
        }
        return n
    }

    /// Erster Tag mit Diktat (für „seit …").
    var ersterTag: String? { tage.keys.min() }

    static func lade(von datei: URL = standardDatei) -> Statistik {
        guard let daten = try? Data(contentsOf: datei),
              let s = try? JSONDecoder().decode(Statistik.self, from: daten)
        else { return Statistik() }
        return s
    }

    func speichere(nach datei: URL = standardDatei) throws {
        try FileManager.default.createDirectory(
            at: datei.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: datei, options: .atomic)
    }

    private static func schluessel(_ d: Date, _ k: Calendar) -> String {
        let c = k.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
