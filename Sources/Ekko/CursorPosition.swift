import AppKit
import ApplicationServices

/// Bildschirm-Position der Text-Einfügemarke der aktiven App über die
/// Accessibility-API. Nicht jede App liefert sie (Electron, manche
/// Web-Views) — dann nil, Aufrufer fällt auf die Sonar-Pille zurück.
enum CursorPosition {
    /// Rechteck der Einfügemarke in AppKit-Bildschirmkoordinaten
    /// (Ursprung unten links), oder nil wenn die App nichts verrät.
    static func caretRect() -> CGRect? {
        let system = AXUIElementCreateSystemWide()
        var fokusRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString,
            &fokusRef) == .success,
            let fokus = fokusRef,
            CFGetTypeID(fokus) == AXUIElementGetTypeID()
        else { return nil }
        let element = unsafeDowncast(fokus, to: AXUIElement.self)

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString,
            &rangeRef) == .success,
            let rangeVal = rangeRef,
            CFGetTypeID(rangeVal) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(
            unsafeDowncast(rangeVal, to: AXValue.self), .cfRange, &range)
        else { return nil }

        // Leere Auswahl (reine Einfügemarke) liefert oft ein Null-Rect —
        // dann das Zeichen davor/danach anfragen.
        for kandidat in [range,
                         CFRange(location: range.location, length: 1),
                         CFRange(location: max(0, range.location - 1),
                                 length: 1)] {
            if let rect = bounds(fuer: kandidat, in: element),
               rect.width > 0 || rect.height > 0 {
                return nachAppKit(rect)
            }
        }
        return nil
    }

    private static func bounds(fuer range: CFRange,
                               in element: AXUIElement) -> CGRect? {
        var r = range
        guard let param = AXValueCreate(.cfRange, &r) else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString,
            param, &boundsRef) == .success,
            let boundsVal = boundsRef,
            CFGetTypeID(boundsVal) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(
            unsafeDowncast(boundsVal, to: AXValue.self), .cgRect, &rect)
        else { return nil }
        return rect
    }

    /// AX liefert globale Koordinaten mit Ursprung OBEN links (Hauptschirm);
    /// AppKit-Fenster rechnen mit Ursprung UNTEN links.
    private static func nachAppKit(_ ax: CGRect) -> CGRect {
        let hauptHoehe = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: ax.origin.x,
                      y: hauptHoehe - ax.origin.y - ax.height,
                      width: ax.width, height: ax.height)
    }
}
