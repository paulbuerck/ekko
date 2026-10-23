// Sources/Ekko/Panes/TeleprompterPane.swift
import SwiftUI

/// Sektion „Teleprompter": Skripte anlegen/bearbeiten, Prompter starten.
/// Skripte liegen als Markdown in
/// ~/Diktate/Teleprompter/.
struct TeleprompterPane: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var skripte: ScriptStore
    @State private var auswahl: ScriptStore.Skript?
    @State private var text = ""
    @State private var umbenennen = false
    @State private var neuerTitel = ""
    @State private var loeschDialog = false
    @State private var fehler: EkkoFehler?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                SeitenKopf(
                    titel: String(localized: "Teleprompter"),
                    untertitel: skripte.skripte.count == 1
                        ? String(localized: "1 Skript — Ekko liest mit und scrollt im Tempo deiner Stimme.")
                        : String(localized: "\(skripte.skripte.count) Skripte — Ekko liest mit und scrollt im Tempo deiner Stimme."))
                Button {
                    do { waehle(try skripte.neu(titel: "Neues Skript")) }
                    catch {
                        fehler = EkkoFehler(text:
                            String(localized: "Anlegen fehlgeschlagen: \(error.localizedDescription)"))
                    }
                } label: {
                    Label("Neues Skript", systemImage: "plus")
                }
                .buttonStyle(.glassProminent)
                .tint(EkkoFarbe.akzent)
            }
            HStack(alignment: .top, spacing: 16) {
                liste
                    .frame(width: 280)
                    .frame(maxHeight: .infinity)
                    .ekkoKarte(innen: 0)
                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ekkoKarte(innen: 0)
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .onAppear {
            skripte.lade()
            if auswahl == nil { waehle(skripte.skripte.first) }
        }
        .ekkoFehler($fehler)
    }

    private var liste: some View {
        VStack(spacing: 0) {
            List(skripte.skripte, id: \.self) { s in
                HStack(spacing: 10) {
                    Image(systemName: "text.viewfinder")
                        .foregroundStyle(EkkoFarbe.akzent)
                        .frame(width: 26, height: 26)
                        .background(EkkoFarbe.akzentWeich,
                            in: RoundedRectangle(
                                cornerRadius: EkkoMetrik.kachelRadius))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.titel).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(auswahl == s
                                ? EkkoFarbe.akzent : Color.primary)
                            .lineLimit(1)
                        Text("\(s.wortzahl) Wörter · ~\(dauerText(s))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                // Petrol-Auswahl wie in Transkripte (statt System-Grau)
                .onTapGesture { auswahl = s }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 1, trailing: 4))
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(auswahl == s ? EkkoFarbe.akzentWeich : Color.clear)
                        .padding(.horizontal, 6))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.vertical, 6)
            .onChange(of: auswahl) { alt, neu in
                if let alt { speichere(alt) }
                text = neu.map(skripte.inhalt) ?? ""
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let skript = auswahl {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text(skript.titel)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Button { neuerTitel = skript.titel; umbenennen = true }
                        label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                    Button(role: .destructive) { loeschDialog = true }
                        label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    Button {
                        speichere(skript)
                        state.prompterStart(skript)
                    } label: {
                        Label("Prompter starten", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.glassProminent)
                    .tint(EkkoFarbe.akzent)
                    .disabled(text.trimmingCharacters(
                        in: .whitespacesAndNewlines).isEmpty
                        || state.prompterLaeuft)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Divider()
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(14)
                Divider()
                HStack(spacing: 5) {
                    Image(systemName: "info.circle").font(.caption)
                    Text("Klartext, Absätze = Sinnabschnitte. Liegt als Markdown in ~/Diktate/Teleprompter/.")
                        .font(.caption)
                    Spacer()
                    Text("\(ScriptStore.wortzahl(text)) Wörter")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .alert("Skript umbenennen", isPresented: $umbenennen) {
                TextField("Titel", text: $neuerTitel)
                Button("Umbenennen") {
                    do {
                        speichere(skript)
                        try skripte.benenneUm(skript, zu: neuerTitel)
                        waehle(skripte.skripte.first {
                            $0.titel == neuerTitel })
                    } catch {
                        fehler = EkkoFehler(text:
                            String(localized: "Umbenennen fehlgeschlagen: \(error.localizedDescription)"))
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .confirmationDialog("»\(skript.titel)« löschen?",
                                isPresented: $loeschDialog) {
                Button("Löschen", role: .destructive) {
                    do {
                        try skripte.loesche(skript)
                        waehle(skripte.skripte.first)
                    } catch {
                        fehler = EkkoFehler(text:
                            String(localized: "Löschen fehlgeschlagen: \(error.localizedDescription)"))
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Kein Skript", systemImage: "text.viewfinder",
                description: Text("Lege oben mit „Neues Skript“ eins an — z. B. für eine Präsentation oder ein Video."))
        }
    }

    private func waehle(_ s: ScriptStore.Skript?) {
        auswahl = s
        text = s.map(skripte.inhalt) ?? ""
    }

    private func speichere(_ s: ScriptStore.Skript) {
        guard skripte.skripte.contains(s),
              skripte.inhalt(s) != text else { return }
        do { try skripte.speichere(s, text: text) }
        catch {
            fehler = EkkoFehler(text:
                String(localized: "Speichern fehlgeschlagen: \(error.localizedDescription)"))
        }
    }

    private func dauerText(_ s: ScriptStore.Skript) -> String {
        let min = s.dauerMinuten
        if min < 1 { return "\(Int(min * 60)) s" }
        return String(format: "%.0f min", min.rounded())
    }
}
