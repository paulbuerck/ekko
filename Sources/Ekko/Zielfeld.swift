import AppKit
import ApplicationServices

/// Wohin geht das Diktat? Beim Start merkt sich Ekko App + fokussiertes
/// Element, vor ⌘V wird der Fokus zurückgesetzt und geprüft, ob dort
/// überhaupt eingefügt werden kann.
/// Bewusst vorsichtig: Weiß AX nichts (Electron ohne
/// AX-Baum, Web-Container), wird wie bisher eingefügt.
enum Zielfeld {
    enum Feldart: Equatable { case editierbar, keinTextfeld, passwort, unbekannt }

    enum Weg: Equatable {
        case einfuegen
        case nurZwischenablage(Grund)
        enum Grund: Equatable { case appGewechselt, passwortfeld, keinTextfeld }
    }

    /// Beim Diktat-Start gemerkt.
    struct Ziel {
        let app: String?
        let element: AXUIElement?
    }

    private static let textRollen: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox"]
    /// Nur Rollen, die sicher keinen Text annehmen. Container (AXGroup,
    /// AXWebArea, AXCell …) bleiben `unbekannt` — dort steckt oft ein
    /// Editor, den AX nicht meldet.
    private static let keineTextRollen: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXSlider", "AXImage",
        "AXMenuItem", "AXMenuBarItem", "AXPopUpButton", "AXStaticText",
        "AXLink"]

    static func feldart(rolle: String?, subrolle: String?,
                        wertSetzbar: Bool?) -> Feldart {
        if subrolle == "AXSecureTextField" { return .passwort }
        if let rolle, textRollen.contains(rolle) { return .editierbar }
        if wertSetzbar == true { return .editierbar }
        if let rolle, keineTextRollen.contains(rolle) { return .keinTextfeld }
        return .unbekannt
    }

    static func entscheide(feld: Feldart, zielAppVorn: Bool) -> Weg {
        guard zielAppVorn else { return .nurZwischenablage(.appGewechselt) }
        switch feld {
        case .passwort: return .nurZwischenablage(.passwortfeld)
        case .keinTextfeld: return .nurZwischenablage(.keinTextfeld)
        case .editierbar, .unbekannt: return .einfuegen
        }
    }

    // MARK: - Accessibility

    static func merke() -> Ziel {
        Ziel(app: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
             element: fokussiertesElement())
    }

    static func fokussiertesElement() -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString, &ref) == .success,
            let ref, CFGetTypeID(ref) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(ref, to: AXUIElement.self)
    }

    static func feldart(von element: AXUIElement?) -> Feldart {
        guard let element else { return .unbekannt }
        var setzbar = DarwinBoolean(false)
        let wertSetzbar = AXUIElementIsAttributeSettable(
            element, kAXValueAttribute as CFString, &setzbar) == .success
            ? setzbar.boolValue : nil
        return feldart(
            rolle: string(element, kAXRoleAttribute),
            subrolle: string(element, kAXSubroleAttribute),
            wertSetzbar: wertSetzbar)
    }

    /// Ist der Fokus innerhalb der Ziel-App auf ein anderes Element
    /// gewandert, das gemerkte Element wieder fokussieren. `true`, wenn
    /// umfokussiert wurde (Aufrufer gibt der App dann kurz Zeit).
    /// Nur zurück auf echte Textfelder — ein gemerkter Container
    /// (AXWebArea, AXGroup) würde den Fokus aus dem Editor ziehen.
    @discardableResult
    static func fokussiereZurueck(_ ziel: Ziel) -> Bool {
        guard let gemerkt = ziel.element,
              feldart(von: gemerkt) == .editierbar
        else { return false }
        if let jetzt = fokussiertesElement(), CFEqual(jetzt, gemerkt) {
            return false
        }
        return AXUIElementSetAttributeValue(
            gemerkt, kAXFocusedAttribute as CFString,
            kCFBooleanTrue) == .success
    }

    /// Textinhalt des Felds (Korrekturen nachlesen). Passwortfelder nie.
    static func wert(von element: AXUIElement) -> String? {
        guard feldart(von: element) != .passwort else { return nil }
        return string(element, kAXValueAttribute)
    }

    /// Rolle/Subrolle fürs Diagnose-Log (kein Inhalt).
    static func beschreibe(_ element: AXUIElement?) -> String {
        guard let element else { return "–" }
        let rolle = string(element, kAXRoleAttribute) ?? "?"
        guard let sub = string(element, kAXSubroleAttribute) else { return rolle }
        return "\(rolle)/\(sub)"
    }

    private static func string(_ element: AXUIElement,
                               _ attribut: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, attribut as CFString, &ref) == .success
        else { return nil }
        return ref as? String
    }
}
