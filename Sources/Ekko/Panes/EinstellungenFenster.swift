import SwiftUI
import AppKit

/// Einstellungen als eigenes Fenster mit Symbol-Reitern (macOS-Standard,
/// HIG). Öffnen: ⌘, · Menüleiste · Zahnrad im Fenster.
@MainActor
enum EinstellungenFenster {
    private static var fenster: NSWindow?

    static func zeige(state: AppState) {
        if let fenster {
            fenster.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for (titel, symbol, inhalt) in [
            (String(localized: "Allgemein"), "gearshape", AnyView(AllgemeinTab())),
            (String(localized: "Diktat"), "waveform", AnyView(DiktatTab())),
            (String(localized: "Berechtigungen"), "lock.shield", AnyView(BerechtigungenTab())),
        ] {
            let host = NSHostingController(rootView: inhalt
                .environmentObject(state)
                .frame(width: 520)
                .fixedSize(horizontal: false, vertical: true))
            host.sizingOptions = .preferredContentSize
            host.title = titel  // Fenstertitel folgt dem Reiter
            let item = NSTabViewItem(viewController: host)
            item.label = titel
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: titel)
            tabs.addTabViewItem(item)
        }
        let f = NSWindow(contentViewController: tabs)
        f.styleMask = [.titled, .closable]
        f.isReleasedWhenClosed = false
        f.center()
        f.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fenster = f
    }
}

private struct AllgemeinTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Darstellung") {
                Picker("Erscheinungsbild", selection: $state.darstellung) {
                    ForEach(Darstellung.allCases) { d in
                        Text(d.label).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                .tint(EkkoFarbe.akzent)
            }
            Section("Sprache") {
                Picker("Sprache", selection: $state.sprache) {
                    ForEach(Sprache.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                Text("Wirkt nach einem Neustart von Ekko.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Ablage") {
                LabeledContent("Transkripte-Ordner", value: "~/Diktate")
                Button("Im Finder zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Diktate")])
                }
                LabeledContent("yt-dlp",
                    value: Downloader.pfad?.path ?? String(localized: "nicht gefunden"))
                LabeledContent("Spracherkennung",
                               value: String(localized: "WhisperKit, on-device, Sprache automatisch"))
            }
        }
        .formStyle(.grouped)
    }
}

private struct DiktatTab: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var qwen = QwenCleanup.shared

    private var qwenStatusText: String {
        switch qwen.status {
        case .nichtGeladen:
            return String(localized: "Modell nicht geladen (lädt beim ersten Diktat; Erst-Download ~2,3 GB)")
        case .laedt(let p):
            return String(localized: "Lädt… \(p) %")
        case .bereit:
            return String(localized: "Bereit (entlädt sich nach 5 min Leerlauf)")
        case .fehler(let f):
            return String(localized: "Fehler: \(f)")
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Hotkey (halten = Diktat)", selection: $state.hotkey) {
                    ForEach(HotkeyModifier.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                Toggle("Töne bei Start und Ende", isOn: $state.toeneAn)
                    .tint(EkkoFarbe.akzent)
                Toggle("Ins Englische übersetzen (translate)",
                       isOn: $state.uebersetzen)
                    .tint(EkkoFarbe.akzent)
            }
            Section("Cleanup") {
                Toggle("Cleanup (LLM)", isOn: $state.cleanupAn)
                    .tint(EkkoFarbe.akzent)
                Picker("Engine", selection: $state.cleanupEngine) {
                    ForEach(CleanupEngine.allCases) { e in
                        Text(e.label).tag(e)
                    }
                }
                if state.cleanupEngine == .qwen {
                    HStack {
                        Text(qwenStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        switch qwen.status {
                        case .bereit:
                            Button("Entladen") { qwen.entlade() }
                        case .laedt:
                            ProgressView().controlSize(.small)
                        default:
                            Button("Modell laden") { Task { await qwen.lade() } }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct BerechtigungenTab: View {
    private func farbe(_ a: Ampel) -> Color {
        switch a { case .gruen: return .green
                   case .gelb: return .yellow
                   case .rot: return .red }
    }

    var body: some View {
        Form {
            Section {
                ForEach(Berechtigung.allCases) { b in
                    HStack {
                        Circle().fill(farbe(b.status)).frame(width: 10, height: 10)
                        VStack(alignment: .leading) {
                            Text(b.name)
                            Text(b.zweck).font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Öffnen…") { b.oeffneEinstellung() }
                    }
                }
            } footer: {
                Text("Ekko braucht diese Freigaben einmalig. Grün = erteilt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
