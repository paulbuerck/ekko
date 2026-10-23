// Sources/Ekko/AppState.swift
import Foundation
import AppKit

/// Ein Diktat im (flüchtigen) Verlauf. `dauer` = Loslassen bis Text
/// fertig, nur bei Live-/Diktat-Pfad bekannt.
struct Diktat: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let zeit: Date
    let dauer: TimeInterval?
    /// Bundle-ID der Ziel-App (fürs Icon im Verlauf), nur RAM.
    var app: String? = nil
    var woerter: Int { text.split(whereSeparator: \.isWhitespace).count }
}

/// Erscheinungsbild der Ekko-Fenster. `system` folgt macOS (HIG-Default).
enum Darstellung: String, CaseIterable, Identifiable {
    case system, hell, dunkel
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return String(localized: "System")
        case .hell: return String(localized: "Hell")
        case .dunkel: return String(localized: "Dunkel")
        }
    }

    static var gespeichert: Darstellung {
        get { Darstellung(rawValue: UserDefaults.standard
            .string(forKey: "darstellung") ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "darstellung") }
    }

    @MainActor
    func anwenden() {
        switch self {
        case .system: NSApp.appearance = nil
        case .hell: NSApp.appearance = NSAppearance(named: .aqua)
        case .dunkel: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// Oberflächensprache. `system` folgt macOS; sonst setzt Ekko sein
/// eigenes „AppleLanguages" (wirkt nach Neustart).
enum Sprache: String, CaseIterable, Identifiable {
    case system, deutsch, englisch
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return String(localized: "Wie System")
        case .deutsch: return String(localized: "Deutsch")
        case .englisch: return "English"
        }
    }

    private static let key = "AppleLanguages"

    /// Nur die App-eigene Domain lesen — `standard` lieferte sonst die
    /// globale Systemliste.
    static var gespeichert: Sprache {
        get {
            let domain = Bundle.main.bundleIdentifier.flatMap {
                UserDefaults.standard.persistentDomain(forName: $0) }
            switch (domain?[key] as? [String])?.first {
            case "de"?: return .deutsch
            case "en"?: return .englisch
            default: return .system
            }
        }
        set {
            switch newValue {
            case .system: UserDefaults.standard.removeObject(forKey: key)
            case .deutsch: UserDefaults.standard.set(["de"], forKey: key)
            case .englisch: UserDefaults.standard.set(["en"], forKey: key)
            }
        }
    }
}

/// Geteilte Wahrheit zwischen dem AppKit-Delegate (EkkoApp) und den
/// SwiftUI-Panes. EkkoApp mutiert, die Views lesen (@EnvironmentObject).
@MainActor
final class AppState: ObservableObject {
    /// Flüchtiger Diktat-Verlauf, jüngstes zuerst, max 20 — bewusst nur im RAM, Diktat-Text kommt nie auf die Platte.
    @Published var verlauf: [Diktat] = []
    /// Dauerhafte Zahlen (Wörter, Diktate, Latenz pro Tag) — kein Text.
    @Published private(set) var statistik = Statistik.lade()
    /// Cleanup-LLM an/aus. Default an;
    /// persistiert, damit der Schalter Neustarts überlebt.
    @Published var cleanupAn: Bool = UserDefaults.standard
        .object(forKey: "cleanupAn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(cleanupAn, forKey: "cleanupAn") }
    }
    /// Welche Engine putzt (Apple FM / Qwen3-4B). Persistiert sich.
    @Published var cleanupEngine: CleanupEngine = .gespeichert {
        didSet { CleanupEngine.gespeichert = cleanupEngine }
    }
    /// Übersetzen-Schalter: alles nach Englisch übersetzen. Default aus.
    @Published var uebersetzen: Bool = UserDefaults.standard
        .bool(forKey: "uebersetzen") {
        didSet { UserDefaults.standard.set(uebersetzen, forKey: "uebersetzen") }
    }
    /// Gewählte Hotkey-Taste. Persistiert sich und meldet Wechsel an den Tap.
    @Published var hotkey: HotkeyModifier = .gespeichert {
        didSet {
            HotkeyModifier.gespeichert = hotkey
            onHotkeyChange?(hotkey)
        }
    }
    /// EkkoApp hängt sich hier ein, um `HotkeyTap.modifier` live zu setzen.
    var onHotkeyChange: ((HotkeyModifier) -> Void)?
    /// Leise Start-/Stopp-Töne beim Diktat (Klang). Default an.
    @Published var toeneAn: Bool = UserDefaults.standard
        .object(forKey: "toeneAn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(toeneAn, forKey: "toeneAn") }
    }
    /// Hell/Dunkel/System — persistiert, wirkt sofort app-weit.
    @Published var darstellung: Darstellung = .gespeichert {
        didSet {
            Darstellung.gespeichert = darstellung
            darstellung.anwenden()
        }
    }
    /// Oberflächensprache — persistiert, wirkt nach Neustart.
    @Published var sprache: Sprache = .gespeichert {
        didSet { Sprache.gespeichert = sprache }
    }
    /// Meeting-Aufnahme läuft (EkkoApp setzt, UI zeigt Knopf + Status).
    @Published var meetingLaeuft = false
    /// Startzeitpunkt der laufenden Aufnahme (UI: Live-Timer).
    @Published var meetingStart: Date?
    /// EkkoApp hängt sich hier ein (UI-Knopf → toggleMeeting).
    var onMeetingToggle: (() -> Void)?

    func meetingToggle() { onMeetingToggle?() }

    /// Teleprompter läuft (EkkoApp setzt, Pane sperrt den Start-Knopf).
    @Published var prompterLaeuft = false
    /// EkkoApp hängt sich hier ein (Pane-Knopf → startePrompter).
    var onPrompterStart: ((ScriptStore.Skript) -> Void)?

    func prompterStart(_ skript: ScriptStore.Skript) {
        onPrompterStart?(skript)
    }

    func merkeDiktat(_ text: String, dauer: TimeInterval? = nil,
                     app: String? = nil) {
        guard !text.isEmpty else { return }
        let diktat = Diktat(text: text, zeit: Date(), dauer: dauer, app: app)
        verlauf.insert(diktat, at: 0)
        // Nur echte Diktate zählen (nur die haben eine Dauer) — Datei-,
        // Meeting- und Prompter-Transkripte würden die Zahlen aufblähen.
        if let dauer {
            statistik.erfasse(woerter: diktat.woerter, dauer: dauer)
            do { try statistik.speichere() }
            catch { print("Statistik speichern: \(error.localizedDescription)") }
        }
        if verlauf.count > 20 { verlauf.removeLast() }
    }
}
