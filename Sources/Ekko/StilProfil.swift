import Foundation

/// Kontext-Formatierung: welche App bekommt welchen Diktat-Ton.
/// Vorbelegung: Mail förmlich, Notizen/Obsidian strukturiert,
/// Messages/Slack knapp; alles andere läuft über das Standard-Putzen.
/// Stil-Profile dürfen bewusst umformulieren und laufen deshalb über die
/// LOCKERE Guardrail, nicht die strenge.
enum StilArt: String, CaseIterable, Codable, Identifiable {
    case standard, foermlich, knapp, strukturiert, roh
    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return String(localized: "Standard (putzen)")
        case .foermlich: return String(localized: "Förmlich (Mail)")
        case .knapp: return String(localized: "Knapp (Chat)")
        case .strukturiert: return String(localized: "Strukturiert (Notizen)")
        case .roh: return String(localized: "Roh (kein Cleanup)")
        }
    }

    /// Prompt der Art. `.standard` nutzt `Cleanup.anweisung`,
    /// `.roh` überspringt das LLM komplett.
    var anweisung: String {
        let basis = """
        Du formatierst Diktat-Transkripte. Immer: entferne Füllwörter \
        (äh, ähm, also, halt, quasi), löse Selbstkorrekturen auf \
        (bei »X, nein, Y« gilt nur Y), gleiche Sprache, keine neuen \
        Inhalte, antworte NUR mit dem Ergebnis.
        """
        switch self {
        case .standard, .roh:
            return Cleanup.anweisung
        case .foermlich:
            return basis + """
            \nZiel: eine förmliche E-Mail-Passage. Ganze, höfliche Sätze; \
            du darfst dafür umformulieren. Absätze bei Themenwechsel. \
            Keine erfundene Anrede oder Grußformel — nur was diktiert wurde.
            """
        case .knapp:
            return basis + """
            \nZiel: eine Kurznachricht. Locker und knapp, keine \
            Schluss-Floskeln, kein förmliches Sie, Emojis nur wenn diktiert.
            """
        case .strukturiert:
            return basis + """
            \nZiel: eine Notiz. Gliedere nach Sinn: kurze Absätze, \
            Aufzählungen mit »- « wo eine Reihung diktiert wurde.
            """
        }
    }
}

/// Eine App-Zuordnung: Bundle-ID → Stil, optional mit eigenem Prompt
/// (überschreibt den Standard-Prompt der Art).
struct ProfilZuordnung: Codable, Equatable, Identifiable {
    var bundleId: String
    var art: StilArt
    var eigenerPrompt: String?
    var id: String { bundleId }

    var wirksameAnweisung: String {
        if let eigen = eigenerPrompt?.trimmingCharacters(
            in: .whitespacesAndNewlines), !eigen.isEmpty {
            return eigen
        }
        return art.anweisung
    }

    /// Vorbelegung. IDE/Terminal bewusst nicht dabei —
    /// unbekannte Apps laufen über Standard.
    static let vorbelegt: [ProfilZuordnung] = [
        .init(bundleId: "com.apple.mail", art: .foermlich),
        .init(bundleId: "com.apple.Notes", art: .strukturiert),
        .init(bundleId: "md.obsidian", art: .strukturiert),
        .init(bundleId: "com.apple.MobileSMS", art: .knapp),
        .init(bundleId: "com.tinyspeck.slackmacgap", art: .knapp),
    ]
}

enum StilProfil {
    /// Zuordnung für eine Bundle-ID, nil wenn keine passt (→ Standard).
    static func finde(_ bundleId: String?,
                      in zuordnungen: [ProfilZuordnung]) -> ProfilZuordnung? {
        guard let bundleId else { return nil }
        return zuordnungen.first { $0.bundleId == bundleId }
    }
}

/// Persistenz + UI-Anbindung der Zuordnungen (UserDefaults als JSON,
/// Muster wie CleanupEngine/HotkeyModifier).
@MainActor
final class ProfilStore: ObservableObject {
    static let shared = ProfilStore()
    private static let key = "stilProfile"

    @Published var zuordnungen: [ProfilZuordnung] {
        didSet { speichere() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let geladen = try? JSONDecoder().decode(
               [ProfilZuordnung].self, from: data) {
            zuordnungen = geladen
        } else {
            zuordnungen = ProfilZuordnung.vorbelegt
        }
    }

    private let defaults: UserDefaults

    func zuordnung(fuer bundleId: String?) -> ProfilZuordnung? {
        StilProfil.finde(bundleId, in: zuordnungen)
    }

    private func speichere() {
        if let data = try? JSONEncoder().encode(zuordnungen) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
