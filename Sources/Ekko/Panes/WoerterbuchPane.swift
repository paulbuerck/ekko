// Sources/Ekko/Panes/WoerterbuchPane.swift
import SwiftUI

/// Wörterbuch als eigener Bereich. Regeln
/// `falsch → richtig` aus ~/Diktate/woerterbuch.txt; Ekko ergänzt sie
/// selbst aus Korrekturen des Nutzers, hier sieht und löscht man sie.
struct WoerterbuchPane: View {
    @ObservedObject private var woerter = WoerterbuchEditor.shared
    @State private var neuFalsch = ""
    @State private var neuRichtig = ""
    @State private var editIndex: Int?
    @State private var fehler: EkkoFehler?
    @State private var ueber: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SeitenKopf(
                titel: String(localized: "Wörterbuch"),
                untertitel: String(localized: "Namen und Fachwörter, die Ekko richtig schreiben soll. Korrigierst du ein Wort nach dem Einfügen, lernt Ekko es hier dazu."))
            eingabe
            liste
        }
        .ekkoSeite()
        .onAppear { woerter.lade() }
        .ekkoFehler($fehler)
    }

    private var eingabe: some View {
        HStack(spacing: 10) {
            TextField("So kommt es an (z. B. schieba)", text: $neuFalsch)
                .textFieldStyle(.roundedBorder)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            TextField("So soll es stehen (z. B. Shiba)", text: $neuRichtig)
                .textFieldStyle(.roundedBorder)
                .onSubmit(speichern)
            Button(editIndex == nil ? "Hinzufügen" : "Speichern", action: speichern)
                .buttonStyle(.glassProminent)
                .tint(EkkoFarbe.akzent)
                .disabled(neuFalsch.trimmingCharacters(in: .whitespaces).isEmpty
                    || neuRichtig.trimmingCharacters(in: .whitespaces).isEmpty)
            if editIndex != nil {
                Button("Abbrechen", action: abbrechen)
            }
        }
        .ekkoKarte(innen: 14)
    }

    @ViewBuilder
    private var liste: some View {
        if woerter.regeln.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "character.book.closed")
                    .font(.system(size: 30))
                    .foregroundStyle(EkkoFarbe.akzent)
                Text("Noch keine Einträge")
                    .font(.system(size: 14, weight: .semibold))
                Text("Lege oben eins an oder korrigiere ein falsch erkanntes Wort direkt nach dem Diktat.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .ekkoKarte(innen: 0)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(woerter.regeln.enumerated()), id: \.offset) { i, r in
                    HStack(spacing: 12) {
                        Text(r.falsch)
                            .foregroundStyle(.secondary)
                            .strikethrough(color: .secondary.opacity(0.5))
                            .frame(maxWidth: 200, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(r.richtig)
                            .font(.system(size: 13.5, weight: .medium))
                        Spacer()
                        Button {
                            neuFalsch = r.falsch; neuRichtig = r.richtig
                            editIndex = i
                        } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                        .help("Bearbeiten")
                        Button(role: .destructive) {
                            do {
                                try woerter.loesche(index: i)
                                if editIndex == i { abbrechen() }
                            } catch {
                                fehler = EkkoFehler(text:
                                    String(localized: "Löschen fehlgeschlagen: \(error.localizedDescription)"))
                            }
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Löschen")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(editIndex == i ? EkkoFarbe.akzentWeich
                        : ueber == i ? Color.primary.opacity(0.045) : .clear)
                    .onHover { drin in
                        withAnimation(.easeOut(duration: 0.12)) { ueber = drin ? i : nil }
                    }
                    if i < woerter.regeln.count - 1 { Divider() }
                }
            }
            .ekkoKarte(innen: 0)
        }
    }

    private func speichern() {
        do {
            if let i = editIndex {
                try woerter.bearbeiten(index: i, falsch: neuFalsch, richtig: neuRichtig)
            } else {
                try woerter.hinzufuegen(falsch: neuFalsch, richtig: neuRichtig)
            }
            abbrechen()
        } catch {
            fehler = EkkoFehler(text:
                String(localized: "Konnte nicht speichern: \(error.localizedDescription)"))
        }
    }

    private func abbrechen() {
        neuFalsch = ""; neuRichtig = ""; editIndex = nil
    }
}
