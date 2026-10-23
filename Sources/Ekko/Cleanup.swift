import Foundation
import FoundationModels

/// Welches LLM putzt. Persistiert wie HotkeyModifier.
enum CleanupEngine: String, CaseIterable, Identifiable {
    case apple, qwen
    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: return String(localized: "Apple (System)")
        case .qwen: return String(localized: "Qwen3-4B (lokal, 2,3 GB)")
        }
    }

    static var gespeichert: CleanupEngine {
        get {
            UserDefaults.standard.string(forKey: "cleanupEngine")
                .flatMap(CleanupEngine.init) ?? .apple
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "cleanupEngine") }
    }
}

/// Diktat-Putz via On-Device-LLM (Engine wählbar: Apple FM oder Qwen3-4B).
/// Guardrail-Prinzip: Cleanup darf nie Text verlieren
/// oder erfinden — bei Zweifel gewinnt das Rohtranskript.
enum Cleanup {
    static let anweisung = """
    Du bereinigst Diktat-Transkripte. Regeln:
    - Entferne Füllwörter (äh, ähm, also, halt, quasi, sozusagen, you know, like, uh, um).
    - Löse Selbstkorrekturen auf: bei »X, nein, Y« gilt nur Y.
    - Korrigiere Interpunktion und Groß-/Kleinschreibung.
    - Ändere sonst NICHTS: keine Umformulierung, keine Ergänzung, keine Zusammenfassung, gleiche Sprache.
    - Antworte NUR mit dem bereinigten Text.
    """

    static func putze(_ text: String) async -> String {
        if CleanupEngine.gespeichert == .qwen {
            if let sauber = await QwenCleanup.shared.putze(
                text, anweisung: QwenCleanup.anweisung) {
                return validate(roh: text, sauber: sauber)
            }
            // Qwen nicht nutzbar (Laden/Inferenz gescheitert) → Apple FM.
        }
        guard case .available = SystemLanguageModel.default.availability
        else { return text }
        do {
            let session = LanguageModelSession(instructions: anweisung)
            let antwort = try await session.respond(to: text)
            return validate(roh: text, sauber: antwort.content)
        } catch {
            return text
        }
    }

    /// Stil-Profile: Diktat mit App-Stil putzen. `.roh` überspringt das LLM,
    /// `.standard` ist der heutige Weg (strenge Guardrail), Stil-Profile
    /// dürfen umformulieren → lockere Guardrail. Stil läuft inline und
    /// deshalb IMMER über Apple FM (Rollenteilungs-Entscheid 2026-07-10:
    /// Qwen 10–18 s/Satz ist inline unbrauchbar, Engine-Picker gilt nur
    /// fürs Standard-Putzen).
    static func putze(_ text: String,
                      zuordnung: ProfilZuordnung?) async -> String {
        guard let zuordnung else { return await putze(text) }
        switch zuordnung.art {
        case .roh:
            return text
        case .standard:
            return await putze(text)
        case .foermlich, .knapp, .strukturiert:
            guard case .available = SystemLanguageModel.default.availability
            else { return text }
            do {
                let session = LanguageModelSession(
                    instructions: zuordnung.wirksameAnweisung)
                let antwort = try await session.respond(to: text)
                return validateLocker(roh: text, sauber: antwort.content)
            } catch {
                return text
            }
        }
    }

    /// Lockere Guardrail für Stil-Profile (sie dürfen umformulieren):
    /// nur Leer-Check + Längen-Ratio — bewusst OHNE Wort-Überlappung,
    /// die würde jede Umformulierung verwerfen. Förmlich darf länger
    /// werden als das Diktat, daher weiteres Band als beim Putzen.
    static func validateLocker(roh: String, sauber: String) -> String {
        let s = sauber.trimmingCharacters(
            in: .whitespacesAndNewlines
                .union(.init(charactersIn: "\"„“»«")))
        guard !s.isEmpty else { return roh }
        let ratio = Double(s.count) / Double(max(roh.count, 1))
        guard ratio >= 0.4, ratio <= 2.0 else { return roh }
        guard bleibtFrageErhalten(roh: roh, sauber: s) else { return roh }
        return s
    }

    /// „Fragen bleiben Fragen": endet das
    /// Diktat als Frage, muss auch das Ergebnis eine enthalten — sonst
    /// hat das Modell geantwortet statt geputzt. Kontext-Ausnahme:
    /// beginnt der letzte Satz mit keinem Frage-Signalwort, ist das »?«
    /// vermutlich Transkriptions-Interpunktion und keine echte Frage →
    /// durchlassen. Nur diese Richtung: Aussage → Frage ist bei Stil-
    /// Profilen legitime Umformulierung (»Könnten Sie …?«).
    static func bleibtFrageErhalten(roh: String, sauber: String) -> Bool {
        let r = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        guard r.hasSuffix("?"), !sauber.contains("?") else { return true }
        let letzterSatz = r.dropLast()
            .split(whereSeparator: { ".!?".contains($0) })
            .last.map(String.init) ?? ""
        let erstesWort = letzterSatz.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .first.map(String.init) ?? ""
        return !frageSignale.contains(erstesWort)
    }

    /// Signalwörter am Satzanfang, die eine echte Frage markieren
    /// (W-Wörter + Verb-Erst-Stellung, DE + EN).
    private static let frageSignale: Set<String> = [
        "wer", "wie", "was", "wann", "wo", "wohin", "woher", "warum",
        "wieso", "weshalb", "welche", "welcher", "welches", "wozu",
        "ist", "sind", "war", "waren", "hat", "hast", "habt", "haben",
        "kann", "kannst", "können", "könnt", "könnte", "könntest",
        "soll", "sollen", "sollte", "solltest", "darf", "dürfen",
        "darfst", "muss", "musst", "müssen", "müsst", "wird", "werden",
        "willst", "wollen", "wollt", "würde", "würdest", "würdet",
        "machst", "macht", "gibt", "geht", "bist", "seid", "brauchst",
        "braucht", "hätte", "hättest", "wäre", "wärst", "weißt", "wisst",
        "who", "what", "when", "where", "why", "how", "which",
        "do", "does", "did", "is", "are", "was", "were", "can", "could",
        "should", "shall", "will", "would", "may", "might", "have", "has",
    ]

    /// Längen-Guardrail (erprobte Werte: 0,5–1,5 der Eingabelänge).
    static func validate(roh: String, sauber: String) -> String {
        let s = sauber.trimmingCharacters(
            in: .whitespacesAndNewlines
                .union(.init(charactersIn: "\"„“»«")))
        guard !s.isEmpty else { return roh }
        let ratio = Double(s.count) / Double(max(roh.count, 1))
        guard ratio >= 0.5, ratio <= 1.5 else { return roh }
        // Wort-Überlappung: Cleanup korrigiert/kürzt nur — der bereinigte
        // Text muss die meisten Original-Wörter enthalten. Eine chattende
        // LLM-Antwort ("Hallo, wie kann ich helfen?") teilt kaum Wörter
        // → verwerfen, Rohtranskript gewinnt.
        let rohWorte = Set(roh.lowercased()
            .split(whereSeparator: { !$0.isLetter }).map(String.init))
        let sauberWorte = Set(s.lowercased()
            .split(whereSeparator: { !$0.isLetter }).map(String.init))
        if !rohWorte.isEmpty {
            let ueberlappung = Double(rohWorte.intersection(sauberWorte).count)
                / Double(rohWorte.count)
            guard ueberlappung >= 0.5 else { return roh }
        }
        // Gleiches Loch wie bei validateLocker: eine Antwort auf die
        // diktierte Frage teilt viele Wörter und passiert die Überlappung.
        guard bleibtFrageErhalten(roh: roh, sauber: s) else { return roh }
        return s
    }
}
