import AppKit

/// Live-Text-Anzeige beim Diktat (Caption am Cursor):
/// dunkles Glas-Panel unter der Einfügemarke der Ziel-App; verrät die
/// App ihre Einfügemarke nicht, schwebt stattdessen die Sonar-Pille
/// unten Bildschirmmitte. Bestätigter Text hell, Hypothese gedimmt.
@MainActor
final class CaptionFenster {
    private var panel: NSPanel?
    private let textFeld = NSTextField(wrappingLabelWithString: "")
    private let kopf = NSTextField(labelWithString: String(localized: "● EKKO HÖRT"))
    private var amCursor = false

    private static let breite: CGFloat = 330
    private static let pillenBreite: CGFloat = 560

    func zeige() {
        kopf.stringValue = String(localized: "● EKKO HÖRT")
        let caret = CursorPosition.caretRect()
        amCursor = caret != nil
        let panel = baue(breite: amCursor ? Self.breite : Self.pillenBreite)
        self.panel = panel
        aktualisiere(bestaetigt: "", hypothese: "")
        positioniere(caret: caret)
        panel.orderFrontRegardless()
    }

    func aktualisiere(bestaetigt: String, hypothese: String) {
        guard let panel else { return }
        let ganz = NSMutableAttributedString()
        let grund: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular)]
        if !bestaetigt.isEmpty {
            ganz.append(NSAttributedString(
                string: bestaetigt,
                attributes: grund.merging(
                    [.foregroundColor: NSColor.white]) { $1 }))
        }
        if !hypothese.isEmpty {
            if !bestaetigt.isEmpty {
                ganz.append(NSAttributedString(string: " ", attributes: grund))
            }
            ganz.append(NSAttributedString(
                string: hypothese,
                attributes: grund.merging(
                    [.foregroundColor: NSColor.white.withAlphaComponent(0.45)]) { $1 }))
        }
        textFeld.attributedStringValue = ganz
        layoute(panel)
    }

    /// Diktat wurde nicht eingefügt (kein Textfeld, App gewechselt,
    /// Paste nicht abgeholt): kurz als Pille zeigen, dass es in der
    /// Zwischenablage liegt — statt still nur ins Log.
    func zeigeHinweis(_ text: String,
                      kopf titel: String = String(localized: "IN DER ZWISCHENABLAGE · ⌘V")) {
        verstecke()
        amCursor = false
        let panel = baue(breite: Self.breite)
        self.panel = panel
        kopf.stringValue = titel
        aktualisiere(bestaetigt: text, hypothese: "")
        positioniere(caret: nil)
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.panel === panel else { return }
            self.verstecke()
        }
    }

    func verstecke() {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Aufbau

    private func baue(breite: CGFloat) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: breite, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let inhalt = NSView()
        // Liquid Glass (macOS 26) statt gemalter Fläche; dunkel getönt,
        // damit der weiße Text über jedem Hintergrund lesbar bleibt.
        let glas = NSGlassEffectView(frame: inhalt.bounds)
        glas.autoresizingMask = [.width, .height]
        glas.cornerRadius = 11
        glas.tintColor = NSColor.black.withAlphaComponent(0.5)
        inhalt.addSubview(glas)

        kopf.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        kopf.textColor = NSColor(srgbRed: 0.286, green: 0.749, blue: 0.792,
                                 alpha: 1)  // Petrol hell
        kopf.translatesAutoresizingMaskIntoConstraints = false

        textFeld.font = NSFont.systemFont(ofSize: 13)
        textFeld.translatesAutoresizingMaskIntoConstraints = false
        textFeld.preferredMaxLayoutWidth = breite - 26

        inhalt.addSubview(kopf)
        inhalt.addSubview(textFeld)
        NSLayoutConstraint.activate([
            kopf.topAnchor.constraint(equalTo: inhalt.topAnchor, constant: 8),
            kopf.leadingAnchor.constraint(
                equalTo: inhalt.leadingAnchor, constant: 13),
            textFeld.topAnchor.constraint(
                equalTo: kopf.bottomAnchor, constant: 3),
            textFeld.leadingAnchor.constraint(
                equalTo: inhalt.leadingAnchor, constant: 13),
            textFeld.trailingAnchor.constraint(
                equalTo: inhalt.trailingAnchor, constant: -13),
            textFeld.bottomAnchor.constraint(
                equalTo: inhalt.bottomAnchor, constant: -9),
        ])
        panel.contentView = inhalt
        return panel
    }

    /// Höhe an den Text anpassen; am Cursor wächst das Panel nach unten,
    /// als Pille nach oben (bleibt über dem Sonar-HUD).
    private func layoute(_ panel: NSPanel) {
        guard let inhalt = panel.contentView else { return }
        let hoehe = inhalt.fittingSize.height
        var frame = panel.frame
        let delta = hoehe - frame.height
        guard abs(delta) > 0.5 else { return }
        if !amCursor { frame.origin.y -= 0 }  // Pille: Unterkante fix
        if amCursor { frame.origin.y -= delta }  // Cursor: Oberkante fix
        frame.size.height = hoehe
        panel.setFrame(frame, display: true)
    }

    private func positioniere(caret: CGRect?) {
        guard let panel else { return }
        let schirm = NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.frame ?? .zero
        var ursprung: CGPoint
        if let caret {
            // unter der Einfügemarke, leicht eingerückt
            ursprung = CGPoint(x: caret.minX - 24,
                               y: caret.minY - panel.frame.height - 8)
        } else {
            // Fallback: unten Bildschirmmitte, über dem Sonar-HUD
            ursprung = CGPoint(
                x: schirm.midX - panel.frame.width / 2,
                y: schirm.minY + 76)
        }
        // auf dem Schirm halten
        ursprung.x = min(max(ursprung.x, schirm.minX + 8),
                         schirm.maxX - panel.frame.width - 8)
        ursprung.y = max(ursprung.y, schirm.minY + 8)
        panel.setFrameOrigin(ursprung)
    }
}
