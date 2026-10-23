import AppKit

/// Welche Modifier-Taste als Halte-Geste den Hotkey auslöst.
/// Nur „solo-selten" genutzte Tasten — linke ⌘/⇧ würden normales Tippen
/// kapern. Die Halte-/Doppeltipp-Semantik (TapDetector) bleibt gleich,
/// egal welche Taste gewählt ist.
enum HotkeyModifier: String, CaseIterable, Identifiable {
    case rechteOption, rechteControl, rechteCommand, fn

    var id: String { rawValue }

    /// Virtueller Keycode der jeweiligen rechten Modifier-Taste.
    var keycode: Int64 {
        switch self {
        case .rechteOption: return 61
        case .rechteControl: return 62
        case .rechteCommand: return 54
        case .fn: return 63
        }
    }

    /// Flag, dessen Anwesenheit im flagsChanged-Event „gedrückt" bedeutet.
    var flag: CGEventFlags {
        switch self {
        case .rechteOption: return .maskAlternate
        case .rechteControl: return .maskControl
        case .rechteCommand: return .maskCommand
        case .fn: return .maskSecondaryFn
        }
    }

    var label: String {
        switch self {
        case .rechteOption: return String(localized: "rechte ⌥ (Option)")
        case .rechteControl: return String(localized: "rechte ⌃ (Control)")
        case .rechteCommand: return String(localized: "rechte ⌘ (Command)")
        case .fn: return "Fn"
        }
    }

    /// Tastensymbol für die Tastenkappe in der UI.
    var symbol: String {
        switch self {
        case .rechteOption: return "⌥"
        case .rechteControl: return "⌃"
        case .rechteCommand: return "⌘"
        case .fn: return "fn"
        }
    }

    /// „rechte" vor der Kappe — bei Fn gibt es keine Seite.
    var seite: String? { self == .fn ? nil : String(localized: "rechte") }

    /// Kurzform für knappe UI-Hinweise („rechte ⌥ halten = Diktat").
    var kurzname: String {
        switch self {
        case .rechteOption: return String(localized: "rechte ⌥")
        case .rechteControl: return String(localized: "rechte ⌃")
        case .rechteCommand: return String(localized: "rechte ⌘")
        case .fn: return "Fn"
        }
    }

    private static let key = "hotkeyModifier"

    /// In UserDefaults gemerkte Wahl; Default rechte ⌥ (bisheriges Verhalten).
    static var gespeichert: HotkeyModifier {
        get {
            UserDefaults.standard.string(forKey: key)
                .flatMap(HotkeyModifier.init) ?? .rechteOption
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
