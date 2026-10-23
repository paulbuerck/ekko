// Sources/Ekko/Panes/TranskriptePane.swift
import SwiftUI
import AppKit

struct TranskriptePane: View {
    @EnvironmentObject var store: TranscriptStore
    @State private var auswahl: TranscriptStore.Transkript?
    @State private var suche = ""
    @State private var loeschKandidat: TranscriptStore.Transkript?
    @State private var umbenennen: TranscriptStore.Transkript?
    @State private var neuerName = ""
    @State private var fehler: EkkoFehler?

    private var gefiltert: [TranscriptStore.Transkript] {
        guard !suche.isEmpty else { return store.transkripte }
        return store.transkripte.filter {
            $0.name.localizedCaseInsensitiveContains(suche) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SeitenKopf(
                titel: String(localized: "Transkripte"),
                untertitel: store.transkripte.count == 1
                    ? String(localized: "1 Transkript aus Meetings und Dateien — als Markdown in ~/Diktate.")
                    : String(localized: "\(store.transkripte.count) Transkripte aus Meetings und Dateien — als Markdown in ~/Diktate."))
            HStack(alignment: .top, spacing: 16) {
                listenSpalte
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
                    .ekkoKarte(innen: 0)
                vorschau
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ekkoKarte(innen: 0)
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .onAppear { store.lade() }
        .alert("Transkript löschen?", isPresented: .constant(loeschKandidat != nil), presenting: loeschKandidat) { t in
            Button("Löschen", role: .destructive) {
                do {
                    try store.loesche(t); auswahl = nil
                } catch {
                    fehler = EkkoFehler(text:
                        String(localized: "Löschen fehlgeschlagen: \(error.localizedDescription)"))
                }
                loeschKandidat = nil
            }
            Button("Abbrechen", role: .cancel) { loeschKandidat = nil }
        } message: { t in Text("„\(t.name)“ wird endgültig gelöscht.") }
        .sheet(item: $umbenennen) { t in
            VStack(spacing: 12) {
                Text("Umbenennen").font(.headline)
                TextField("Name", text: $neuerName)
                HStack {
                    Button("Abbrechen") { umbenennen = nil }
                    Button("Sichern") {
                        do {
                            try store.benenneUm(t, zu: neuerName)
                            umbenennen = nil
                        } catch {
                            fehler = EkkoFehler(text:
                                String(localized: "Umbenennen fehlgeschlagen: \(error.localizedDescription)"))
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .tint(EkkoFarbe.akzent)
                }
            }.padding().frame(width: 320)
        }
        .ekkoFehler($fehler)
    }

    private var listenSpalte: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Suchen", text: $suche)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
            Divider()
            if gefiltert.isEmpty {
                Text(suche.isEmpty ? "Noch keine Transkripte" : "Nichts gefunden")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(gefiltert) { t in zeile(t) }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
            }
        }
    }

    private func zeile(_ t: TranscriptStore.Transkript) -> some View {
        HStack(spacing: 11) {
            ikonKachel(t)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(auswahl == t
                        ? EkkoFarbe.akzent : Color.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if t.istMeeting {
                        Text("Meeting")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(EkkoFarbe.meetingWeich, in: Capsule())
                            .foregroundStyle(EkkoFarbe.meeting)
                    }
                    Text(t.datum, style: .date)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { auswahl = t }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 1, trailing: 4))
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8)
                .fill(auswahl == t ? EkkoFarbe.akzentWeich : Color.clear)
                .padding(.horizontal, 6))
        .contextMenu {
            Button("Umbenennen…") { neuerName = t.name; umbenennen = t }
            Button("Im Finder zeigen") {
                NSWorkspace.shared.activateFileViewerSelecting([t.url]) }
            Button("Kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(store.inhalt(t), forType: .string) }
            Divider()
            Button("Löschen", role: .destructive) { loeschKandidat = t }
        }
    }

    @ViewBuilder
    private var vorschau: some View {
        if let t = auswahl {
            VStack(spacing: 0) {
                vorschauLeiste(t)
                Divider()
                ScrollView {
                    Text(store.inhalt(t))
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(24)
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 28))
                    .foregroundStyle(EkkoFarbe.akzent)
                Text("Kein Transkript gewählt")
                    .font(.system(size: 14, weight: .semibold))
                Text("Links eins auswählen — Meetings und importierte Dateien landen hier.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Icon-Kachel: Meeting = Mikro/Orange, Datei = Doc/Petrol.
    @ViewBuilder private func ikonKachel(
        _ t: TranscriptStore.Transkript) -> some View {
        let farbe = t.istMeeting ? EkkoFarbe.meeting : EkkoFarbe.akzent
        let weich = t.istMeeting ? EkkoFarbe.meetingWeich : EkkoFarbe.akzentWeich
        let symbol = t.istMeeting ? "mic" : "doc.text"
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(farbe)
            .frame(width: 26, height: 26)
            .background(weich,
                        in: RoundedRectangle(cornerRadius: EkkoMetrik.kachelRadius))
    }

    /// Vorschau-Werkzeugleiste (rechtsbündig).
    @ViewBuilder private func vorschauLeiste(
        _ t: TranscriptStore.Transkript) -> some View {
        HStack(spacing: 4) {
            Text(t.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            tbKnopf("pencil", "Umbenennen") {
                neuerName = t.name; umbenennen = t }
            tbKnopf("folder", "Im Finder zeigen") {
                NSWorkspace.shared.activateFileViewerSelecting([t.url]) }
            tbKnopf("doc.on.doc", "Kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    store.inhalt(t), forType: .string) }
            tbKnopf("trash", "Löschen", gefahr: true) {
                loeschKandidat = t }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private func tbKnopf(
        _ symbol: String, _ titel: LocalizedStringKey,
        gefahr: Bool = false, _ aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(gefahr ? Color.red : .secondary)
        .help(titel)
    }
}
