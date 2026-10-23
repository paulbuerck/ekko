import AppKit
import CoreGraphics

/// Text in die aktive App einfügen: Pasteboard sichern → Text als
/// Versprechen (Data-Provider) setzen → ⌘V via CGEvent posten
/// (Bedienungshilfen-Freigabe nötig; robuster als osascript/System
/// Events) → Pasteboard erst wiederherstellen, wenn die Ziel-App den
/// Text tatsächlich abgeholt hat (eine fixe Wartezeit verlor bei
/// langsamer Ziel-App das Diktat). Holt bis `timeout` niemand ab, gilt der Paste
/// als gescheitert und das Diktat bleibt in der Zwischenablage liegen.
@MainActor
enum Paster {
    enum Ergebnis: Equatable { case eingefuegt, nichtAbgeholt }

    /// nspasteboard.org-Konvention: Clipboard-Manager ignorieren den
    /// Eintrag — sonst holt z. B. Maccy den Text ab und täuscht Erfolg vor.
    static let transientTyp = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Hält den laufenden Provider, bis der Paste abgeschlossen ist.
    private static var aktiv: Lieferant?

    static func paste(
        _ text: String,
        auf pb: NSPasteboard = .general,
        timeout: TimeInterval = 2,
        nachlauf: TimeInterval = 0.5,
        sendeEinfuegen: @MainActor () -> Void = postCmdV,
        fertig: ((Ergebnis) -> Void)? = nil
    ) {
        aktiv?.schliesseAb()
        let saved = sichere(pb)
        let lieferant = Lieferant(text: text, pb: pb, saved: saved,
                                  nachlauf: nachlauf, fertig: fertig)
        aktiv = lieferant

        pb.clearContents()
        let item = NSPasteboardItem()
        item.setDataProvider(lieferant, forTypes: [.string])
        item.setData(Data(), forType: transientTyp)
        pb.writeObjects([item])
        lieferant.eigeneAenderung = pb.changeCount

        sendeEinfuegen()

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            if !lieferant.abgeholt { lieferant.beende(.nichtAbgeholt) }
        }
    }

    static func postCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9  // 'v'
        let down = CGEvent(
            keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(
            keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        usleep(5_000)  // manche Apps verschlucken Down+Up ohne Pause
        up?.post(tap: .cghidEventTap)
    }

    /// Alle Einträge mit allen Typen — nicht nur Text, sonst gehen
    /// kopierte Bilder/RTF beim Diktieren verloren.
    typealias Sicherung = [[(NSPasteboard.PasteboardType, Data)]]

    static func sichere(_ pb: NSPasteboard) -> Sicherung {
        (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { typ in
                item.data(forType: typ).map { (typ, $0) }
            }
        }
    }

    static func stelleWiederHer(_ sicherung: Sicherung, auf pb: NSPasteboard) {
        pb.clearContents()
        let items = sicherung.map { typen in
            let item = NSPasteboardItem()
            for (typ, daten) in typen { item.setData(daten, forType: typ) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }

    /// Nur in die Zwischenablage legen, ohne ⌘V und ohne Wieder-
    /// herstellung — für „Ziel-App nicht mehr vorn": der Nutzer fügt
    /// selbst ein, der Text muss liegen bleiben.
    static func kopiere(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Liefert den Text erst auf Anfrage; die Anfrage ist der Beweis,
    /// dass eingefügt wurde.
    @MainActor
    private final class Lieferant: NSObject, NSPasteboardItemDataProvider {
        nonisolated let text: String
        let pb: NSPasteboard
        let saved: Paster.Sicherung
        let nachlauf: TimeInterval
        let fertig: ((Ergebnis) -> Void)?
        var eigeneAenderung = 0
        private(set) var abgeholt = false
        private var erledigt = false

        init(text: String, pb: NSPasteboard, saved: Paster.Sicherung,
             nachlauf: TimeInterval, fertig: ((Ergebnis) -> Void)?) {
            self.text = text
            self.pb = pb
            self.saved = saved
            self.nachlauf = nachlauf
            self.fertig = fertig
        }

        /// Ein neues Diktat verdrängt dieses: Stand jetzt festschreiben.
        func schliesseAb() { beende(abgeholt ? .eingefuegt : .nichtAbgeholt) }

        nonisolated func pasteboard(
            _ pasteboard: NSPasteboard?, item: NSPasteboardItem,
            provideDataForType type: NSPasteboard.PasteboardType
        ) {
            item.setString(text, forType: type)
            // Nicht sofort zurückschreiben: Apps lesen nach der ersten
            // Anfrage oft noch einmal (Notizen fügte sonst den ALTEN
            // Inhalt ein, Live-Befund 2026-10-22).
            Task { @MainActor in
                guard !self.abgeholt else { return }
                self.abgeholt = true
                DispatchQueue.main.asyncAfter(deadline: .now() + self.nachlauf) {
                    self.beende(.eingefuegt)
                }
            }
        }

        func beende(_ ergebnis: Ergebnis) {
            guard !erledigt else { return }
            erledigt = true
            if Paster.aktiv === self { Paster.aktiv = nil }
            switch ergebnis {
            case .eingefuegt:
                // Nur zurückschreiben, wenn seither niemand sonst
                // kopiert hat.
                if pb.changeCount == eigeneAenderung {
                    Paster.stelleWiederHer(saved, auf: pb)
                }
            case .nichtAbgeholt:
                // Versprechen durch echte Daten ersetzen, damit das
                // Diktat nach dem Ende des Providers abrufbar bleibt.
                if pb.changeCount == eigeneAenderung {
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                }
            }
            fertig?(ergebnis)
        }
    }
}
