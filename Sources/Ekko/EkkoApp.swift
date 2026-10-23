import AppKit
import ApplicationServices
import AVFoundation
import UniformTypeIdentifiers
import os

/// App-Kern: Hotkey halten → Aufnahme → WhisperKit → Paste, dazu Meeting,
/// Import, Teleprompter, Fenster und Pille. Statusitem zeigt ○/●/⏳.
@main
@MainActor
final class EkkoApp: NSObject, NSApplicationDelegate {
    private let hotkey = HotkeyTap()
    private let recorder = Recorder()
    private let transcriber = WhisperTranscriber()
    private let woerterbuch = Woerterbuch()
    private let hud = SonarHUD()
    private let meeting = MeetingRecorder()
    private let systemAudio = SystemAudioRecorder()
    private var statusItem: NSStatusItem!
    private let state = AppState()
    private let store = TranscriptStore()
    private lazy var queue = TranskriptionsQueue(
        transkribierer: transcriber, woerterbuch: woerterbuch,
        aufTranskript: { [weak self] _, _ in self?.store.lade() })
    private var recording = false
    private var pegelTimer: Timer?
    private let log = Logger(subsystem: "de.paul.ekko", category: "app")
    // Live-Text: Caption-Panel + Streaming-Loop-Steuerung
    private let caption = CaptionFenster()
    private var liveSteuerung: LiveSteuerung?
    /// Voriges Diktat wird noch abgeschlossen (Abschluss-Pass, Cleanup,
    /// Paste). Solange keine neue Aufnahme: sie würde den Puffer des
    /// alten Diktats übernehmen und es still verwerfen.
    private var abschlussLaeuft = false
    /// Zeitpunkt des Loslassens — Latenz zählt ab hier, nicht ab
    /// Tastendruck (bis 2026-10-23 war Sprechzeit mitgemessen).
    private var losgelassenAm: Date?
    private var liveTask: Task<Void, Never>?
    // Stil-Profile + Einfügen: Ziel-App und fokussiertes Feld beim
    // Diktat-Start
    private var ziel = Zielfeld.Ziel(app: nil, element: nil)
    // Lernen aus Korrekturen: Feld nach dem Paste einmal nachlesen (nur RAM)
    private var beobachtung: (element: AXUIElement, text: String)?
    private var beobachtungsTimer: Timer?
    private let meldung = CaptionFenster()
    // Teleprompter
    private let skripte = ScriptStore()
    private var prompter: PrompterFenster?
    private var prompterSteuerung: LiveSteuerung?

    static func main() {
        // Bench-Modus: Ekko --bench datei.wav [läufe] — headless STT-Messung
        let args = CommandLine.arguments
        // WhisperKit-Bench: Ekko --bench-whisper <clip> <modell> [läufe] [de|en|auto]
        if args.count >= 4, args[1] == "--bench-whisper" {
            let clip = URL(fileURLWithPath: args[2])
            let modell = args[3]
            let laeufe = args.count >= 5 ? Int(args[4]) ?? 3 : 3
            let sprache: String? = args.count >= 6 && args[5] != "auto"
                ? args[5] : nil
            Task {
                await WhisperBench.lauf(clip: clip, modell: modell,
                                        laeufe: laeufe, sprache: sprache)
                exit(0)
            }
            RunLoop.main.run()
            return
        }
        // Biasing-Messung: Ekko --bench-prompt <modell> "<Wort, Wort>" <clip>...
        if args.count >= 5, args[1] == "--bench-prompt" {
            let woerter = args[3].split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let clips = args[4...].map { URL(fileURLWithPath: $0) }
            Task {
                await PromptBench.lauf(modell: args[2], woerter: woerter,
                                       clips: clips)
                exit(0)
            }
            RunLoop.main.run()
            return
        }
        // Live-Pfad-Probe: Ekko --stream-probe <clip> [sekunden] —
        // fährt den ECHTEN Live-Text-Pfad (streame + LiveKonfirmation) headless
        // mit Datei-Audio in simulierter Echtzeit statt Mikro.
        if args.count >= 3, args[1] == "--stream-probe" {
            setvbuf(stdout, nil, _IONBF, 0)
            let clip = URL(fileURLWithPath: args[2])
            let dauer = args.count >= 4 ? Double(args[3]) ?? 30 : 30
            Task { @MainActor in
                await StreamProbe.lauf(clip: clip, sekunden: dauer)
                exit(0)
            }
            RunLoop.main.run()
            return
        }
        // Streaming-Bench: Ekko --bench-stream <clip> <modell> [maxSekunden]
        if args.count >= 4, args[1] == "--bench-stream" {
            let clip = URL(fileURLWithPath: args[2])
            let modell = args[3]
            let maxS = args.count >= 5 ? Double(args[4]) ?? 120 : 120
            Task {
                await StreamBench.lauf(clip: clip, modell: modell,
                                       maxSekunden: maxS)
                exit(0)
            }
            RunLoop.main.run()
            return
        }
        if args.count >= 3, args[1] == "--bench" {
            setvbuf(stdout, nil, _IONBF, 0)  // Prints sofort sichtbar
            let url = URL(fileURLWithPath: args[2])
            let runs = args.count >= 4 ? Int(args[3]) ?? 3 : 3
            Task { @MainActor in
                let t = Transcriber()
                do {
                    try await t.prepare()
                    for i in 1...runs {
                        let t0 = Date()
                        let text = try await t.transcribeFile(url)
                        print(String(format: "Lauf %d: %.2f s: %@",
                                     i, Date().timeIntervalSince(t0), text))
                    }
                } catch {
                    print("Bench-Fehler: \(error)")
                }
                exit(0)
            }
            RunLoop.main.run()
            return
        }
        // Qwen-Probe: Ekko --qwen "<text>|@<testdatei>" [anweisungsdatei]
        // Testdatei: eine Eingabe pro Zeile. Anweisungsdatei erlaubt
        // Prompt-Iteration ohne Rebuild. (Erst-Lauf lädt das Modell.)
        if args.count >= 3, args[1] == "--qwen" {
            setvbuf(stdout, nil, _IONBF, 0)
            let eingaben: [String]
            if args[2].hasPrefix("@"),
               let inhalt = try? String(
                   contentsOfFile: String(args[2].dropFirst()), encoding: .utf8) {
                eingaben = inhalt.split(separator: "\n").map(String.init)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            } else {
                eingaben = [args[2]]
            }
            let anweisung: String
            if args.count >= 4,
               let a = try? String(contentsOfFile: args[3], encoding: .utf8) {
                anweisung = a.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                anweisung = QwenCleanup.anweisung
            }
            Task { @MainActor in
                let qwen = QwenCleanup.shared
                let statusTask = Task { @MainActor in
                    var zuletzt = -1
                    while true {
                        try await Task.sleep(for: .seconds(2))
                        if case .laedt(let p) = qwen.status, p != zuletzt {
                            print("lädt… \(p) %")
                            zuletzt = p
                        }
                    }
                }
                for text in eingaben {
                    let t0 = Date()
                    guard let sauber = await qwen.putze(text, anweisung: anweisung)
                    else {
                        if case .fehler(let f) = qwen.status { print("Fehler: \(f)") }
                        exit(1)
                    }
                    print("IN : \(text)")
                    print(String(format: "OUT (%.1f s): %@",
                                 Date().timeIntervalSince(t0), sauber))
                }
                statusTask.cancel()
                print("RAM: \(Int(residentSpeicherMB())) MB")
                exit(0)
            }
            RunLoop.main.run()
            return
        }
        // Apple-FM-Probe: Ekko --apple "<text>|@<testdatei>" — Vergleichsbasis
        if args.count >= 3, args[1] == "--apple" {
            setvbuf(stdout, nil, _IONBF, 0)
            let eingaben: [String]
            if args[2].hasPrefix("@"),
               let inhalt = try? String(
                   contentsOfFile: String(args[2].dropFirst()), encoding: .utf8) {
                eingaben = inhalt.split(separator: "\n").map(String.init)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            } else {
                eingaben = [args[2]]
            }
            Task { @MainActor in
                for text in eingaben {
                    let t0 = Date()
                    let sauber = await Cleanup.putze(text)
                    print("IN : \(text)")
                    print(String(format: "OUT (%.1f s): %@",
                                 Date().timeIntervalSince(t0), sauber))
                }
                exit(0)
            }
            RunLoop.main.run()
            return
        }
        // Datei-Modus: Ekko --file <pfad> — Video/Audio transkribieren
        if args.count >= 3, args[1] == "--file" {
            setvbuf(stdout, nil, _IONBF, 0)
            let quelle = URL(fileURLWithPath: args[2])
            Task { @MainActor in
                let t = Transcriber()
                let wb = Woerterbuch()
                do {
                    try await t.prepare()
                    let t0 = Date()
                    let audio = try await MediaExtractor.audioURL(for: quelle)
                    let text = wb.apply(try await t.transcribeFile(audio))
                    if audio != quelle {
                        try? FileManager.default.removeItem(at: audio)
                    }
                    let ziel = try TranskriptAblage.schreibe(
                        quelle: quelle, text: text)
                    print(String(format: "Transkript in %.1f s -> %@",
                                 Date().timeIntervalSince(t0), ziel.path))
                    print(text)
                } catch {
                    print("Fehler: \(error.localizedDescription)")
                    exit(1)
                }
                exit(0)
            }
            RunLoop.main.run()
            return
        }
        let app = NSApplication.shared
        let delegate = EkkoApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.darstellung.anwenden()
        EkkoSchrift.registriere()
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength)
        setSymbol("○")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Ekko", action: nil, keyEquivalent: ""))
        let dateiItem = NSMenuItem(
            title: String(localized: "Datei transkribieren…"),
            action: #selector(waehleDatei), keyEquivalent: "o")
        dateiItem.target = self
        menu.addItem(dateiItem)
        let meetingItem = NSMenuItem(
            title: String(localized: "Meeting starten/stoppen"),
            action: #selector(toggleMeeting), keyEquivalent: "m")
        meetingItem.target = self
        menu.addItem(meetingItem)
        let cleanupItem = NSMenuItem(
            title: String(localized: "Cleanup (LLM)"), action: #selector(toggleCleanup(_:)),
            keyEquivalent: "")
        cleanupItem.target = self
        cleanupItem.state = state.cleanupAn ? .on : .off
        menu.addItem(cleanupItem)
        let letztesItem = NSMenuItem(
            title: String(localized: "Letztes Diktat einfügen"),
            action: #selector(fuegeLetztesEin), keyEquivalent: "")
        letztesItem.target = self
        menu.addItem(letztesItem)
        let einstItem = NSMenuItem(
            title: String(localized: "Einstellungen…"), action: #selector(oeffneEinstellungen),
            keyEquivalent: ",")
        einstItem.target = self
        menu.addItem(einstItem)
        let oeffnenItem = NSMenuItem(
            title: String(localized: "Ekko öffnen"), action: #selector(oeffneFenster),
            keyEquivalent: "e")
        oeffnenItem.target = self
        menu.addItem(oeffnenItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: String(localized: "Beenden"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))
        statusItem.menu = menu
        installiereHauptmenue()

        // Eingabemonitoring explizit prüfen/anfordern — tapCreate kann
        // trotz fehlender Freigabe „gelingen" und still taub bleiben:
        if !CGPreflightListenEventAccess() {
            log.warning("Eingabemonitoring fehlt — fordere an")
            CGRequestListenEventAccess()
            setSymbol("⛔️")
        }
        // Bedienungshilfen nötig fürs Einfügen (CGEvent ⌘V) — nur warnen:
        if !AXIsProcessTrusted() {
            log.warning("Bedienungshilfen fehlen — Einfügen (⌘V) funktioniert nicht")
        }
        hotkey.onAction = { [weak self] action in self?.handle(action) }
        hotkey.modifier = state.hotkey
        state.onHotkeyChange = { [weak self] m in self?.hotkey.modifier = m }
        state.onMeetingToggle = { [weak self] in self?.toggleMeeting() }
        state.onPrompterStart = { [weak self] s in self?.startePrompter(s) }
        guard hotkey.start() else {
            log.error("Event Tap verweigert — Eingabemonitoring-Rechte fehlen")
            print("Event Tap verweigert — Eingabemonitoring erlauben, neu starten.")
            NSApplication.shared.terminate(nil)
            return
        }
        Task {
            do {
                try await transcriber.prepare()
                self.log.info("WhisperKit bereit (small, prewarmt)")
            } catch {
                self.log.error("WhisperKit-Setup: \(error.localizedDescription)")
            }
        }
        hud.setup()
        hud.onToggleRecord = { [weak self] in
            guard let self else { return }
            self.recording ? self.stopDictation() : self.startDictation()
        }
        hud.history = { [weak self] in self?.state.verlauf.map(\.text) ?? [] }
        hud.onFileDrop = { [weak self] url in
            self?.transcribeMediaFile(url)
        }
        hud.onOpenApp = { [weak self] in
            guard let self else { return }
            HauptFenster.zeige(state: self.state, store: self.store, queue: self.queue, skripte: self.skripte)
        }

        log.info("Ekko-Skeleton läuft")
        print("Ekko-Skeleton läuft. Rechte ⌥ halten = Diktat.")
    }

    private func handle(_ action: TapAction) {
        switch action {
        case .start:
            startDictation()
        case .stop:
            stopDictation()
        case .doubleTap:
            if meeting.laeuft {
                stopMeeting()
            } else if !recording {
                startMeeting()
            }
        case .cancel:
            // Kurztipp bricht nur eine laufende Aufnahme ab — nie ein
            // Diktat, das gerade abgeschlossen wird.
            guard recording else { return }
            liveSteuerung?.brichAb()
            liveSteuerung = nil
            caption.verstecke()
            _ = recorder.stop()
            recording = false
            pegelTimer?.invalidate()
            setSymbol("○")
            hud.update(.idle, level: 0)
            queueFortsetzen()
        }
    }

    /// Hebt `queue.pausiert` auf und stößt die Warteschlange wieder an.
    /// Muss auf JEDEM Pfad laufen, der `startDictation()` je verlässt,
    /// sonst hängen Import-Items für immer in `.wartet`.
    private func queueFortsetzen() {
        queue.pausiert = false
        Task { await queue.verarbeiteNaechstes() }
    }

    // MARK: - Teleprompter

    /// Prompter starten: Panel zeigen, Mikro an, Streaming-Loop füttert
    /// den Aligner. Ein Mikro, eine Aufgabe — läuft nicht neben
    /// Diktat/Meeting.
    private func startePrompter(_ skript: ScriptStore.Skript) {
        guard !recording, !meeting.laeuft, prompter == nil else { return }
        let text = skripte.inhalt(skript)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        do {
            try recorder.start()
        } catch {
            log.error("Prompter-Aufnahme: \(error.localizedDescription)")
            NSSound.beep()
            return
        }
        state.prompterLaeuft = true
        queue.pausiert = true
        setSymbol("●")
        let fenster = PrompterFenster(titel: skript.titel, skript: text)
        fenster.onStopp = { [weak self] in self?.stoppePrompter() }
        fenster.zeige()
        prompter = fenster
        let steuerung = LiveSteuerung()
        prompterSteuerung = steuerung
        Task {
            do {
                let finaltext = try await self.transcriber.streame(
                    samples: { [recorder] in recorder.samplesSnapshot() },
                    steuerung: steuerung,
                    onUpdate: { stand in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  self.prompterSteuerung === steuerung
                            else { return }
                            self.prompter?.hoere(
                                stand.bestaetigt + " " + stand.hypothese)
                        }
                    })
                self.schliessePrompterAb(finaltext: finaltext)
            } catch {
                self.log.error("Prompter-Stream: \(error.localizedDescription)")
                self.schliessePrompterAb(finaltext: nil)
            }
        }
    }

    private func stoppePrompter() {
        // Loop beenden — schliessePrompterAb übernimmt danach.
        prompterSteuerung?.beende()
    }

    /// Aufräumen nach dem Prompter-Lauf: WAV + Transkript in ~/Diktate
    /// wie beim Meeting (WAV nach erfolgreichem Transkript weg).
    private func schliessePrompterAb(finaltext: String?) {
        let buffer = recorder.stop()
        prompter?.schliesse()
        prompter = nil
        prompterSteuerung = nil
        state.prompterLaeuft = false
        setSymbol("○")
        queueFortsetzen()
        guard let finaltext, !finaltext.isEmpty, let buffer else { return }
        Task {
            do {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd-HHmm"
                let wav = TranskriptAblage.verzeichnis
                    .appendingPathComponent(
                        "\(f.string(from: Date()))-prompter.wav")
                let datei = try AVAudioFile(
                    forWriting: wav, settings: buffer.format.settings)
                try datei.write(from: buffer)
                let ziel = try TranskriptAblage.schreibe(
                    quelle: wav, text: finaltext)
                try? FileManager.default.removeItem(at: wav)
                self.state.merkeDiktat(finaltext)
                self.log.info("Prompter-Transkript: \(ziel.path)")
            } catch {
                self.log.error("Prompter-Ablage: \(error.localizedDescription)")
            }
        }
    }

    private func startDictation() {
        guard !recording, prompter == nil else { return }
        guard !abschlussLaeuft else {
            log.info("Start ignoriert — voriges Diktat wird noch abgeschlossen")
            return
        }
        lerneAusKorrektur()
        // Ziel-App VOR allem anderen merken — sie bestimmt das
        // Stil-Profil beim Einfügen (Ekko selbst wird nie frontmost,
        // Caption-Panel ist nonactivating).
        ziel = Zielfeld.merke()
        do {
            try recorder.start()
            recording = true
            Klang.spieleStart()
            queue.pausiert = true
            setSymbol("●")
            hud.update(.recording, level: 0)
            pegelTimer?.invalidate()
            pegelTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                // Synchron statt Task: ein nach invalidate() eingereihter
                // Task setzte das HUD nach dem Reset wieder (hängende Pille).
                MainActor.assumeIsolated {
                    guard let self, self.recording else { return }
                    self.hud.update(.recording, level: self.recorder.level)
                }
            }
            starteLiveText()
        } catch {
            log.error("Aufnahme-Start: \(error.localizedDescription)")
        }
    }

    /// Live-Text: Caption zeigen und Streaming-Loop starten. Der Loop
    /// läuft bis `beende()` (Loslassen → Finaltext → Paste) oder
    /// `brichAb()` (Esc). Wirft er (Modell nicht bereit), fällt das
    /// Diktat auf den alten Voll-Transkriptions-Weg zurück.
    private func starteLiveText() {
        caption.zeige()
        let steuerung = LiveSteuerung()
        liveSteuerung = steuerung
        let t0 = Date()
        liveTask = Task {
            do {
                let finaltext = try await self.transcriber.streame(
                    samples: { [recorder] in recorder.samplesSnapshot() },
                    steuerung: steuerung,
                    onUpdate: { stand in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  self.liveSteuerung === steuerung
                            else { return }
                            self.caption.aktualisiere(
                                bestaetigt: stand.bestaetigt,
                                hypothese: stand.hypothese)
                        }
                    })
                // Identitäts-Guard wie in onUpdate: startet ein neues
                // Diktat, bevor der Abschluss-Pass fertig ist, gehört
                // recorder/liveSteuerung schon der neuen Session — der
                // alte Task darf sie nicht stoppen/nullen.
                if let finaltext, self.liveSteuerung === steuerung {
                    self.schliesseDiktatAb(
                        rohtext: finaltext, seit: self.losgelassenAm ?? t0)
                } else if self.liveSteuerung === steuerung, !self.recording {
                    // Kein Ergebnis ohne Abbruch: aufräumen, sonst bleiben
                    // HUD und Abschluss-Sperre stehen.
                    self.liveSteuerung = nil
                    self.caption.verstecke()
                    _ = self.recorder.stop()
                    self.pegelTimer?.invalidate()
                    self.setSymbol("○")
                    self.hud.update(.idle, level: 0)
                    self.abschlussLaeuft = false
                    self.queueFortsetzen()
                }
            } catch {
                self.log.error("Live-Text: \(error.localizedDescription)")
                guard self.liveSteuerung === steuerung else { return }
                self.caption.verstecke()
                self.liveSteuerung = nil
                if !self.recording {
                    // Taste schon losgelassen — alter Weg übernimmt.
                    self.legacyStop(seit: self.losgelassenAm ?? t0)
                }
            }
        }
    }

    private func stopDictation() {
        guard recording else { return }
        recording = false
        losgelassenAm = Date()
        abschlussLaeuft = true
        Klang.spieleStopp()
        pegelTimer?.invalidate()
        setSymbol("⏳")
        hud.update(.transcribing, level: 0)
        pegelTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hud.update(.transcribing, level: 0)
            }
        }
        if let steuerung = liveSteuerung {
            // Live-Pfad: Loop macht den Abschluss-Pass und ruft
            // schliesseDiktatAb — Mikro stoppt dort (Puffer bleibt
            // bis dahin für den Abschluss-Pass verfügbar).
            steuerung.beende()
        } else {
            legacyStop(seit: Date())
        }
    }

    /// Paste nur, wenn die beim Diktat-Start gemerkte Ziel-App noch vorn
    /// ist: nach Fokuswechsel während des
    /// Putzens landet der Text sonst falsch formatiert in der falschen
    /// App — dann nur Zwischenablage, Nutzer fügt selbst mit ⌘V ein.
    /// Zusätzlich (2026-10-22): Fokus innerhalb der App aufs
    /// gemerkte Feld zurück, kein ⌘V in Passwort- oder Nicht-Textfelder,
    /// und jeder Nicht-Einfüge-Fall wird sichtbar statt nur geloggt.
    private func fuegeEin(_ text: String) async {
        let vorn = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let appVorn = ziel.app == nil || vorn == nil || vorn == ziel.app
        let umfokussiert = appVorn && Zielfeld.fokussiereZurueck(ziel)
        if umfokussiert {
            try? await Task.sleep(for: .milliseconds(80))
        }
        let aktuell = Zielfeld.fokussiertesElement()
        let feld = Zielfeld.feldart(von: aktuell)
        let weg = Zielfeld.entscheide(feld: feld, zielAppVorn: appVorn)
        log.info("Einfügen: ziel=\(self.ziel.app ?? "?", privacy: .public) vorn=\(vorn ?? "?", privacy: .public) gemerkt=\(Zielfeld.beschreibe(self.ziel.element), privacy: .public) jetzt=\(Zielfeld.beschreibe(aktuell), privacy: .public) umfokussiert=\(umfokussiert) feld=\(String(describing: feld), privacy: .public) weg=\(String(describing: weg), privacy: .public)")
        switch weg {
        case .einfuegen:
            let t0 = Date()
            Paster.paste(text, fertig: { [weak self] ergebnis in
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                self?.log.info("Paste-Ergebnis: \(String(describing: ergebnis), privacy: .public) nach \(ms) ms")
                guard ergebnis == .nichtAbgeholt else {
                    self?.beobachte(aktuell, text: text)
                    return
                }
                self?.caption.zeigeHinweis(text)
            })
        case .nurZwischenablage(let grund):
            Paster.kopiere(text)
            log.info("Nicht eingefügt (\(String(describing: grund)), \(self.ziel.app ?? "?") → \(vorn ?? "?")) — Text nur in Zwischenablage")
            caption.zeigeHinweis(text)
        }
    }

    /// Lernen: Nach erfolgreichem Paste das Feld merken; beim nächsten Diktat
    /// oder nach 30 s einmal nachlesen.
    private func beobachte(_ element: AXUIElement?, text: String) {
        beobachtungsTimer?.invalidate()
        beobachtung = element.map { ($0, text) }
        guard beobachtung != nil else { return }
        beobachtungsTimer = Timer.scheduledTimer(
            withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.lerneAusKorrektur() }
        }
    }

    /// Nachbesserung → Wörterbuch-Regeln, sichtbar gemeldet und im
    /// Wörterbuch löschbar (nie still).
    private func lerneAusKorrektur() {
        beobachtungsTimer?.invalidate()
        guard let (element, text) = beobachtung else { return }
        beobachtung = nil
        guard let feld = Zielfeld.wert(von: element) else { return }
        let editor = WoerterbuchEditor.shared
        editor.lade()
        let regeln = KorrekturLerner.vorschlaege(
            eingefuegt: text, feldtext: feld,
            bekannt: Set(editor.regeln.map { $0.falsch.lowercased() }))
        log.info("Lernen: \(regeln.count, privacy: .public) Regel(n)")
        guard !regeln.isEmpty else { return }
        for r in regeln {
            try? editor.hinzufuegen(falsch: r.falsch, richtig: r.richtig)
        }
        meldung.zeigeHinweis(
            regeln.map { "\($0.falsch) → \($0.richtig)" }
                .joined(separator: "\n"),
            kopf: String(localized: "GELERNT · WÖRTERBUCH"))
    }

    /// Menü „Letztes Diktat einfügen" — Rettung, wenn ein Paste daneben
    /// ging. Kurz warten, bis das
    /// Statusmenü zu ist und der Fokus zurück in der App liegt.
    @objc private func fuegeLetztesEin() {
        guard let text = state.verlauf.first?.text else { NSSound.beep(); return }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            Paster.paste(text)
        }
    }

    /// Finaltext aus dem Live-Pfad: Aufnahme beenden, putzen, einfügen.
    private func schliesseDiktatAb(rohtext: String, seit t0: Date) {
        _ = recorder.stop()
        caption.verstecke()
        liveSteuerung = nil
        // Stufe 1: Loslassen → Abschluss-Pass fertig (Spracherkennung)
        let abschlussPass = Date().timeIntervalSince(t0)
        Task {
            let t1 = Date()
            var text = self.woerterbuch.apply(rohtext)
            if self.state.cleanupAn {
                text = await Cleanup.putze(
                    text, zuordnung: ProfilStore.shared
                        .zuordnung(fuer: self.ziel.app))
            }
            // Stufe 2: Wörterbuch + Cleanup · gesamt = Loslassen → Text fertig
            let nachbearbeitung = Date().timeIntervalSince(t1)
            let dt = Date().timeIntervalSince(t0)
            self.log.info("Latenz: Abschluss-Pass \(Int(abschlussPass * 1000), privacy: .public) ms · Nachbearbeitung \(Int(nachbearbeitung * 1000), privacy: .public) ms (Cleanup \(self.state.cleanupAn ? "an" : "aus", privacy: .public)) · gesamt \(Int(dt * 1000), privacy: .public) ms · \(text.count, privacy: .public) Zeichen")
            print(String(format: "Live-Transkript in %.2f s: %@", dt, text))
            if !text.isEmpty {
                self.state.merkeDiktat(text, dauer: dt, app: self.ziel.app)
                await self.fuegeEin(text)
            }
            self.pegelTimer?.invalidate()
            self.setSymbol("○")
            self.hud.update(.idle, level: 0)
            self.abschlussLaeuft = false
            self.queueFortsetzen()
        }
    }

    /// Alter Weg (Revert-Pfad): Gesamtpuffer nach dem Loslassen in einem
    /// Stück transkribieren. Läuft, wenn der Live-Pfad nicht startete.
    private func legacyStop(seit t0: Date) {
        guard let buffer = recorder.stop() else {
            pegelTimer?.invalidate()
            setSymbol("○")
            hud.update(.idle, level: 0)
            abschlussLaeuft = false
            queueFortsetzen()
            return
        }
        Task {
            do {
                var text = self.woerterbuch.apply(
                    try await self.transcriber.transcribe(buffer))
                if self.state.cleanupAn {
                    text = await Cleanup.putze(
                        text, zuordnung: ProfilStore.shared
                            .zuordnung(fuer: self.ziel.app))
                }
                let dt = Date().timeIntervalSince(t0)
                self.log.info("Transkript in \(String(format: "%.2f", dt)) s: \(text.count) Zeichen")
                print(String(format: "Transkript in %.2f s: %@", dt, text))
                if !text.isEmpty {
                    self.state.merkeDiktat(text, dauer: dt, app: self.ziel.app)
                    await self.fuegeEin(text)
                }
            } catch {
                self.log.error("Transkription: \(error.localizedDescription)")
            }
            self.pegelTimer?.invalidate()
            self.setSymbol("○")
            self.hud.update(.idle, level: 0)
            self.abschlussLaeuft = false
            self.queueFortsetzen()
        }
    }

    @objc private func waehleDatei() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie,
                                     .audio, .wav, .mp3, .mpeg4Audio]
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Video- oder Audio-Datei transkribieren")
        if panel.runModal() == .OK, let url = panel.url {
            transcribeMediaFile(url)
        }
    }

    func transcribeMediaFile(_ url: URL) {
        guard !recording else { return }  // ein Mikro, eine Aufgabe
        setSymbol("⏳")
        hud.update(.transcribing, level: 0)
        let t0 = Date()
        Task {
            do {
                let audio = try await MediaExtractor.audioURL(for: url)
                let text = self.woerterbuch.apply(
                    try await self.transcriber.transcribeFile(audio))
                if audio != url {
                    try? FileManager.default.removeItem(at: audio)
                }
                let ziel = try TranskriptAblage.schreibe(
                    quelle: url, text: text)
                self.state.merkeDiktat(text)
                self.log.info("Datei-Transkript in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s: \(ziel.path)")
                NSWorkspace.shared.activateFileViewerSelecting([ziel])
            } catch {
                self.log.error("Datei-Transkription: \(error.localizedDescription)")
                NSSound.beep()
            }
            self.setSymbol("○")
            self.hud.update(.idle, level: 0)
        }
    }

    private func startMeeting() {
        guard prompter == nil else { return }  // ein Mikro, eine Aufgabe
        do {
            let url = try meeting.start()
            log.info("Meeting-Aufnahme: \(url.path)")
            Task {
                do { try await self.systemAudio.start(neben: url) }
                catch {
                    self.log.error("System-Audio-Start: \(error.localizedDescription)")
                }
            }
            state.meetingLaeuft = true
            state.meetingStart = Date()
            setSymbol("●●")
            pegelTimer?.invalidate()
            pegelTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.hud.update(.meeting, level: 0.5)
                }
            }
        } catch {
            log.error("Meeting-Start: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    private func stopMeeting() {
        // State immer zurücksetzen, auch wenn stop() nil liefert — sonst
        // bleibt die UI im Zombie-„läuft"-Zustand hängen.
        state.meetingLaeuft = false
        state.meetingStart = nil
        guard let wav = meeting.stop() else { return }
        pegelTimer?.invalidate()
        setSymbol("⏳")
        hud.update(.transcribing, level: 0)
        Task {
            let systemWav = await self.systemAudio.stop()
            do {
                let text = self.woerterbuch.apply(
                    try await self.transcriber.transcribeFile(wav))
                let ziel = try TranskriptAblage.schreibe(
                    quelle: wav, text: text)
                self.state.merkeDiktat(text)
                self.log.info("Meeting-Transkript: \(ziel.path)")
                NSWorkspace.shared.activateFileViewerSelecting([ziel])
                if let systemWav {
                    let andere = try await self.transcriber
                        .transcribeFile(systemWav)
                    if !andere.isEmpty {
                        let kombi = "## Du (Mikro)\n\n\(text)\n\n## Andere (System-Audio)\n\n\(andere)"
                        _ = try TranskriptAblage.schreibe(
                            quelle: systemWav, text: kombi)
                    }
                }
                try? FileManager.default.removeItem(at: wav)
                if let systemWav {
                    try? FileManager.default.removeItem(at: systemWav)
                }
                self.log.info("Meeting-WAV(s) nach erfolgreichem Transkript gelöscht")
            } catch {
                self.log.error("Meeting-Transkription: \(error.localizedDescription)")
                NSSound.beep()
            }
            self.setSymbol("○")
            self.hud.update(.idle, level: 0)
        }
    }

    @objc private func toggleMeeting() {
        meeting.laeuft ? stopMeeting() : startMeeting()
    }

    /// Standard-App-Menüleiste. `.regular` liefert ohne sie kein
    /// Bearbeiten-Menü — dann fehlen ⌘X/⌘C/⌘V/⌘A in Textfeldern
    /// (z.B. Link ins Import-Feld einfügen ging nicht).
    private func installiereHauptmenue() {
        let haupt = NSMenu()

        let appItem = NSMenuItem()
        haupt.addItem(appItem)
        let appMenu = NSMenu()
        let einst = NSMenuItem(title: String(localized: "Einstellungen…"),
                               action: #selector(oeffneEinstellungen),
                               keyEquivalent: ",")
        einst.target = self
        appMenu.addItem(einst)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Ekko ausblenden"),
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Ekko beenden"),
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        haupt.addItem(editItem)
        let editMenu = NSMenu(title: String(localized: "Bearbeiten"))
        editMenu.addItem(withTitle: String(localized: "Widerrufen"),
                         action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: String(localized: "Wiederholen"),
                         action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "Ausschneiden"),
                         action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Kopieren"),
                         action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Einfügen"),
                         action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "Alles auswählen"),
                         action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = haupt
    }

    @objc private func toggleCleanup(_ sender: NSMenuItem) {
        state.cleanupAn.toggle()
        sender.state = state.cleanupAn ? .on : .off
    }

    @objc private func oeffneEinstellungen() {
        EinstellungenFenster.zeige(state: state)
    }

    @objc private func oeffneFenster() {
        HauptFenster.zeige(state: state, store: store, queue: queue, skripte: skripte)
    }

    /// Dock-Icon-Klick (ohne sichtbares Fenster) öffnet das Hauptfenster.
    /// Ohne das tut der Klick nichts — Fenster ging nur übers Menüleisten-○.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            HauptFenster.zeige(state: state, store: store, queue: queue, skripte: skripte)
        }
        return true
    }

    private func setSymbol(_ s: String) {
        statusItem.button?.title = s
    }
}
