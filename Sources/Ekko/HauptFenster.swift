// Sources/Ekko/HauptFenster.swift
import SwiftUI
import AppKit

enum Bereich: String, CaseIterable, Identifiable {
    case start = "Start"
    case woerterbuch = "Wörterbuch"
    case stil = "Stil"
    case transkripte = "Transkripte"
    case teleprompter = "Teleprompter"
    case importe = "Import"
    var id: String { rawValue }
    /// Angezeigter Name (lokalisiert; `rawValue` bleibt die stabile ID).
    var titel: String {
        switch self {
        case .start: return String(localized: "Start")
        case .woerterbuch: return String(localized: "Wörterbuch")
        case .stil: return String(localized: "Stil")
        case .transkripte: return String(localized: "Transkripte")
        case .teleprompter: return String(localized: "Teleprompter")
        case .importe: return String(localized: "Import")
        }
    }
    var symbol: String {
        switch self {
        case .start: return "house"
        case .woerterbuch: return "character.book.closed"
        case .stil: return "textformat"
        case .transkripte: return "doc.text"
        case .teleprompter: return "text.viewfinder"
        case .importe: return "square.and.arrow.down"
        }
    }

    /// Seitenleisten-Gruppen (Diktat-Werkzeuge oben).
    static let gruppen: [(titel: String?, bereiche: [Bereich])] = [
        (String(localized: "Diktat"), [.start, .woerterbuch, .stil]),
        (String(localized: "Bibliothek"), [.transkripte, .teleprompter, .importe]),
    ]
}

@MainActor
enum HauptFenster {
    private static var fenster: NSWindow?

    static func zeige(state: AppState, store: TranscriptStore,
                      queue: TranskriptionsQueue, skripte: ScriptStore) {
        if let fenster {
            fenster.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = HauptView().environmentObject(state).environmentObject(store)
            .environmentObject(queue).environmentObject(skripte)
        let f = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable,
                        .fullSizeContentView],
            backing: .buffered, defer: false)
        f.title = "Ekko"
        // Seitenleiste reicht bis oben (macOS-Standard für Sidebar-Apps)
        f.titlebarAppearsTransparent = true
        f.titleVisibility = .hidden
        f.isReleasedWhenClosed = false
        // contentViewController zuerst — es überschreibt sonst die Größe;
        // danach Größe/Minimum explizit setzen, sonst kollabiert die
        // NavigationSplitView auf die winzige Fitting-Size.
        f.contentViewController = NSHostingController(rootView: root)
        f.contentMinSize = NSSize(width: 760, height: 500)
        f.setContentSize(NSSize(width: 1000, height: 680))
        f.setFrameAutosaveName("EkkoHauptFenster")
        f.center()
        f.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fenster = f
    }
}

private struct HauptView: View {
    @EnvironmentObject var state: AppState
    @State private var auswahl: Bereich = .start
    @State private var ueber: Bereich?

    var body: some View {
        NavigationSplitView {
            // Auswahl selbst gezeichnet (Petrol statt System-Blau):
            // native List-Selektion folgt sonst dem System-Akzent.
            List {
                marke
                ForEach(Bereich.gruppen.indices, id: \.self) { g in
                    let gruppe = Bereich.gruppen[g]
                    Section {
                        ForEach(gruppe.bereiche) { eintrag($0) }
                    } header: {
                        if let titel = gruppe.titel { Text(titel) }
                    }
                }
            }
            .listStyle(.sidebar)
            .tint(EkkoFarbe.akzent)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) { bereitFuss }
        } detail: {
            seite
                .id(auswahl)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .animation(.easeOut(duration: 0.18), value: auswahl)
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    /// Aktuelle Seite — weich eingeblendet beim Wechsel.
    @ViewBuilder
    private var seite: some View {
            switch auswahl {
            case .start: StartPane()
            case .woerterbuch: WoerterbuchPane()
            case .stil: StilPane()
            case .transkripte: TranskriptePane()
            case .teleprompter: TeleprompterPane()
            case .importe: ImportPane()
            }
    }

    /// Markenkopf oben in der Seitenleiste.
    private var marke: some View {
        HStack(spacing: 8) {
            AppIconBild(groesse: 30)
            Text("Ekko")
                .font(EkkoSchrift.sora(19, gewicht: 600))
                .tracking(-0.3)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .listRowSeparator(.hidden)
    }

    /// Eintrag mit Petrol-Auswahl statt System-Blau.
    private func eintrag(_ b: Bereich) -> some View {
        Label(b.titel, systemImage: b.symbol)
            .foregroundStyle(auswahl == b ? EkkoFarbe.akzent : Color.primary)
            .fontWeight(auswahl == b ? .semibold : .regular)
            // Ganze Zeile klickbar, nicht nur der Text
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { auswahl = b }
            }
            .onHover { drin in
                withAnimation(.easeOut(duration: 0.12)) { ueber = drin ? b : nil }
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: EkkoMetrik.kachelRadius)
                    .fill(auswahl == b ? EkkoFarbe.akzentWeich
                          : ueber == b ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 6))
    }

    /// Zurückhaltender Sonar-Fuß in der Seitenleiste —
    /// plus sichtbarer Meeting-Knopf (war nur Doppeltipp/⌘M, unentdeckbar).
    private var bereitFuss: some View {
        VStack(spacing: 0) {
            Divider()
            meetingKnopf
                .padding(.horizontal, 10)
                .padding(.top, 10)
            HStack(spacing: 9) {
                ImpulsZeichen(farbe: state.meetingLaeuft
                    ? EkkoFarbe.meeting : EkkoFarbe.akzent, groesse: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.meetingLaeuft ? "Meeting läuft" : "Bereit")
                        .font(.system(size: 11.5, weight: .semibold))
                    if state.meetingLaeuft {
                        Text("Mikro + System-Audio")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    } else {
                        HotkeyHinweis(hotkey: state.hotkey, rest: "halten",
                                      groesse: 11.5)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    EinstellungenFenster.zeige(state: state)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Einstellungen (⌘,)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    /// Meeting starten/stoppen — Status sichtbar, Zeit läuft live mit.
    private var meetingKnopf: some View {
        Button(action: { state.meetingToggle() }) {
            HStack(spacing: 7) {
                Image(systemName: state.meetingLaeuft
                    ? "stop.fill" : "record.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text(state.meetingLaeuft ? "Stopp" : "Meeting aufnehmen")
                    .font(.system(size: 12, weight: .semibold))
                if state.meetingLaeuft, let start = state.meetingStart {
                    Text(start, style: .timer)
                        .font(.system(size: 12, weight: .semibold)
                            .monospacedDigit())
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .glassEffect(
                .regular
                    .tint(EkkoFarbe.meeting.opacity(state.meetingLaeuft ? 0.85 : 0.15))
                    .interactive(),
                in: .rect(cornerRadius: 10))
            .foregroundStyle(state.meetingLaeuft
                ? Color.white : EkkoFarbe.meeting)
        }
        .buttonStyle(.plain)
        .help("Meeting-Aufnahme (auch: \(state.hotkey.kurzname) doppelt tippen oder ⌘M)")
    }
}
