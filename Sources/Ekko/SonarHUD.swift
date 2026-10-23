import AppKit

/// Ekko-Sonar: eigenes HUD. Idle = Punkt. Aufnahme = Kapsel mit
/// pulsierendem Punkt + Live-Wellenform. Transkription =
/// wandernde Welle. Hover = Knöpfe: Aufnahme · Verlauf · App.
@MainActor
final class SonarHUD {
    enum Zustand { case idle, recording, meeting, transcribing }

    var onToggleRecord: (() -> Void)?
    var onFileDrop: ((URL) -> Void)?
    var onOpenApp: (() -> Void)?
    var history: () -> [String] = { [] }

    private var panel: NSPanel!
    private var sonar: SonarView!
    private var glas: NSGlassEffectView!
    private var buttons: NSStackView!
    private var hovered = false
    private var zustand: Zustand = .idle

    private static let petrol = NSColor(
        calibratedRed: 0.10, green: 0.55, blue: 0.53, alpha: 1)

    private let dotSize: CGFloat = 26      // Panel idle (Punkt + Rand)
    private let activeSize = NSSize(width: 176, height: 40)

    func setup() {
        let rect = NSRect(origin: .zero, size: activeSize)
        panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false

        let content = HoverView(frame: rect)
        content.onHover = { [weak self] inside in self?.setHovered(inside) }
        content.onFileDrop = { [weak self] url in self?.onFileDrop?(url) }
        panel.contentView = content

        // Liquid Glass als Kapsel (macOS 26), dunkel getönt für Kontrast
        glas = NSGlassEffectView(frame: rect)
        glas.autoresizingMask = [.width, .height]
        glas.cornerRadius = rect.height / 2
        glas.tintColor = NSColor.black.withAlphaComponent(0.4)
        glas.isHidden = true
        content.addSubview(glas)

        sonar = SonarView(frame: rect)
        sonar.autoresizingMask = [.width, .height]
        content.addSubview(sonar)

        buttons = NSStackView(frame: rect)
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.distribution = .equalCentering
        buttons.spacing = 14
        buttons.addArrangedSubview(knopf("record.circle", #selector(H.record)))
        buttons.addArrangedSubview(knopf("clock.arrow.circlepath", #selector(H.verlauf)))
        buttons.addArrangedSubview(knopf("macwindow", #selector(H.app)))
        buttons.isHidden = true
        buttons.autoresizingMask = [.width, .height]
        // Sonst hält die (versteckte) Knopfleiste das Panel auf ~77 pt
        // Mindestbreite — der Idle-Punkt saß dann 25 pt rechts der Mitte.
        buttons.setClippingResistancePriority(.defaultLow, for: .horizontal)
        buttons.setClippingResistancePriority(.defaultLow, for: .vertical)
        content.addSubview(buttons)

        position()
        panel.orderFrontRegardless()
        update(.idle, level: 0)
    }

    private var handler: H!
    private func knopf(_ symbol: String, _ action: Selector) -> NSButton {
        if handler == nil { handler = H(hud: self) }
        let b = NSButton(
            image: NSImage(systemSymbolName: symbol,
                           accessibilityDescription: nil)!,
            target: handler, action: action)
        b.isBordered = false
        b.contentTintColor = .white
        return b
    }

    /// Zustand + Pegel (30-Hz-Ticker in EkkoApp treibt recording-Pegel).
    func update(_ z: Zustand, level: Float) {
        zustand = z
        sonar.zustand = z
        sonar.level = CGFloat(level)
        sonar.tint = Self.petrol
        let groß = z != .idle || hovered
        let size = groß ? activeSize
                        : NSSize(width: dotSize, height: dotSize)
        if panel.frame.size != size {
            // Weich auf-/zuklappen statt springen
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(rahmen(fuer: size), display: true)
            }
        }
        glas.isHidden = !groß
        glas.cornerRadius = size.height / 2
        buttons.isHidden = !(hovered && z == .idle)
        sonar.isHidden = !buttons.isHidden
        sonar.needsDisplay = true
    }

    private func setHovered(_ inside: Bool) {
        hovered = inside
        update(zustand, level: CGFloat(sonar.level).isNaN ? 0 : Float(sonar.level))
    }

    private func position() {
        panel.setFrame(rahmen(fuer: panel.frame.size), display: true)
    }

    /// Unten mittig, oberhalb von Dock/Home-Leiste.
    private func rahmen(fuer size: NSSize) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: panel.frame.origin, size: size)
        }
        return NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 16,
            width: size.width, height: size.height)
    }

    /// Ziel-Aktionen (NSButton braucht NSObject-Target).
    @MainActor
    private final class H: NSObject {
        unowned let hud: SonarHUD
        init(hud: SonarHUD) { self.hud = hud }
        @objc func record() { hud.onToggleRecord?() }
        @objc func app() { hud.onOpenApp?() }
        @objc func verlauf() {
            let menu = NSMenu()
            let eintraege = hud.history()
            if eintraege.isEmpty {
                menu.addItem(NSMenuItem(
                    title: String(localized: "Noch keine Diktate"), action: nil, keyEquivalent: ""))
            }
            for text in eintraege.prefix(5) {
                let kurz = text.count > 60
                    ? String(text.prefix(60)) + "…" : text
                let item = NSMenuItem(
                    title: kurz, action: #selector(copyItem(_:)),
                    keyEquivalent: "")
                item.target = self
                item.representedObject = text
                menu.addItem(item)
            }
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: hud.panel.frame.height),
                       in: hud.panel.contentView)
        }
        @objc func copyItem(_ sender: NSMenuItem) {
            guard let text = sender.representedObject as? String else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

/// Zeichnet Ekkos Pille. Idle = Punkt. Aufnahme/Meeting = pulsierender
/// Punkt + Live-Wellenform aus dem Pegel der letzten ~0,7 s (läuft von
/// rechts nach links). Transkription = ruhige, wandernde Welle.
/// Eigener 60-Hz-Takt, solange aktiv — flüssig, unabhängig vom
/// Pegel-Timer in EkkoApp.
final class SonarView: NSView {
    var zustand: SonarHUD.Zustand = .idle {
        didSet { zustand == .idle ? stoppeTakt() : starteTakt() }
    }
    /// Jeder neue Pegel schiebt die Wellenform um einen Balken weiter.
    var level: CGFloat = 0 {
        didSet {
            guard zustand == .recording || zustand == .meeting else { return }
            verlauf.removeFirst()
            verlauf.append(min(1, max(0, level)))
        }
    }
    var tint: NSColor = .systemTeal

    private static let balken = 22
    private var verlauf = Array(repeating: CGFloat(0), count: SonarView.balken)
    /// Geglättete Balkenhöhen (federn zum Ziel statt zu springen).
    private var hoehen = Array(repeating: CGFloat(0), count: SonarView.balken)
    private var punktPuls: CGFloat = 0
    private var phase: CGFloat = 0
    private var takt: Timer?

    private func starteTakt() {
        guard takt == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        takt = t
    }

    private func stoppeTakt() {
        takt?.invalidate()
        takt = nil
        verlauf = Array(repeating: 0, count: Self.balken)
        hoehen = Array(repeating: 0, count: Self.balken)
        needsDisplay = true
    }

    private func tick() {
        phase += 1.0 / 60
        let n = Self.balken
        for i in 0..<n {
            let ziel: CGFloat
            switch zustand {
            case .recording, .meeting:
                // In der Mitte höher, zu den Rändern flacher.
                let x = CGFloat(i) / CGFloat(n - 1)
                let huelle = 0.45 + 0.55 * sin(x * .pi)
                ziel = pow(verlauf[i], 0.7) * huelle
            case .transcribing:
                ziel = 0.18 + 0.14 * (1 + sin(phase * 5 - CGFloat(i) * 0.45)) / 2
            case .idle:
                ziel = 0
            }
            // Feder: schnell hoch, etwas langsamer runter.
            let k: CGFloat = ziel > hoehen[i] ? 0.45 : 0.18
            hoehen[i] += (ziel - hoehen[i]) * k
        }
        let pulsZiel = zustand == .transcribing
            ? 0.3 + 0.3 * sin(phase * 4) : (verlauf.last ?? 0)
        punktPuls += (pulsZiel - punktPuls) * 0.3
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        guard zustand != .idle else {
            ctx.setFillColor(tint.cgColor)
            ctx.fillEllipse(in: CGRect(x: bounds.midX - 4, y: bounds.midY - 4,
                                       width: 8, height: 8))
            return
        }

        // Kapsel selbst ist NSGlassEffectView (SonarHUD) — hier nur Inhalt.
        let farbe: NSColor = zustand == .meeting
            ? NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.15, alpha: 1)
            : tint

        // Punkt links mit Glühen (pulsiert mit Pegel bzw. „denkt nach")
        let punkt = CGPoint(x: bounds.minX + bounds.height / 2, y: bounds.midY)
        let glow = 5 + 7 * punktPuls
        ctx.setFillColor(farbe.withAlphaComponent(0.18 + 0.2 * punktPuls).cgColor)
        ctx.fillEllipse(in: CGRect(x: punkt.x - glow, y: punkt.y - glow,
                                   width: glow * 2, height: glow * 2))
        ctx.setFillColor(farbe.cgColor)
        ctx.fillEllipse(in: CGRect(x: punkt.x - 4.5, y: punkt.y - 4.5,
                                   width: 9, height: 9))

        // Wellenform rechts, gespiegelt um die Mitte
        let links = punkt.x + 16
        let rechts = bounds.maxX - bounds.height / 2 + 4
        let n = Self.balken
        let schritt = (rechts - links) / CGFloat(n)
        let breite = max(2, schritt * 0.55)
        let maxH = bounds.height - 16
        for i in 0..<n {
            let h = max(3, hoehen[i] * maxH)
            let x = links + CGFloat(i) * schritt + (schritt - breite) / 2
            let balken = NSBezierPath(
                roundedRect: CGRect(x: x, y: bounds.midY - h / 2,
                                    width: breite, height: h),
                xRadius: breite / 2, yRadius: breite / 2)
            farbe.withAlphaComponent(0.45 + 0.55 * min(1, hoehen[i] * 1.6))
                .setFill()
            balken.fill()
        }
    }
}

/// Meldet Maus-Hover und nimmt Datei-Drops an.
final class HoverView: NSView {
    var onHover: ((Bool) -> Void)?
    var onFileDrop: ((URL) -> Void)?

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL])
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = NSURL(
            from: sender.draggingPasteboard) as URL? else { return false }
        onFileDrop?(url)
        return true
    }
}
