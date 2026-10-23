// Sources/Ekko/Panes/StartPane.swift
import SwiftUI
import AppKit

/// Startseite: Begrüßung, Kennzahlen
/// dieser Sitzung, darunter der Verlauf mit Uhrzeit. Verlauf bleibt
/// flüchtig im RAM (Datenschutz).
struct StartPane: View {
    @EnvironmentObject var state: AppState
    @State private var kopiert: Diktat.ID?
    @State private var ueber: Diktat.ID?

    private var begruessung: String {
        let stunde = Calendar.current.component(.hour, from: Date())
        let gruss = (5..<11).contains(stunde) ? String(localized: "Guten Morgen")
            : (11..<18).contains(stunde) ? String(localized: "Guten Tag") : String(localized: "Guten Abend")
        let name = NSFullUserName().split(separator: " ").first.map(String.init)
        return name.map { "\(gruss), \($0)" } ?? gruss
    }

    private var latenz: String {
        guard let mittel = state.statistik.mittlereLatenz(tage: 30) else { return "–" }
        return mittel.formatted(.number.precision(.fractionLength(1))) + " s"
    }

    private var seit: String {
        guard let erster = state.statistik.ersterTag,
              let datum = try? Date(erster + "T12:00:00Z", strategy: .iso8601)
        else { return String(localized: "noch keine") }
        return String(localized:
            "seit \(datum.formatted(.dateTime.day().month(.abbreviated).year()))")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(begruessung)
                    .font(EkkoSchrift.titel())
                    .tracking(-0.4)
                HotkeyHinweis(hotkey: state.hotkey,
                              rest: "halten und sprechen — Ekko schreibt dort, wo dein Cursor steht.")
                    .foregroundStyle(.secondary)
            }
            kennzahlen
            verlauf
        }
        .ekkoSeite()
    }

    // MARK: Kennzahlen

    private var kennzahlen: some View {
        HStack(spacing: 0) {
            kennzahl(state.statistik.woerterGesamt.formatted(), String(localized: "Wörter"), seit)
            Divider().padding(.vertical, 4)
            kennzahl("\(state.statistik.diktate())", String(localized: "Diktate"), String(localized: "heute"))
            Divider().padding(.vertical, 4)
            let serie = state.statistik.streak()
            kennzahl("\(serie)", serie == 1 ? String(localized: "Tag in Folge") : String(localized: "Tage in Folge"),
                     String(localized: "mit mindestens einem Diktat"))
            Divider().padding(.vertical, 4)
            kennzahl(latenz, String(localized: "Ø bis Text"), String(localized: "letzte 30 Tage"))
        }
        .ekkoKarte(innen: 18)
    }

    private func kennzahl(_ wert: String, _ titel: String,
                          _ hinweis: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(wert)
                .font(EkkoSchrift.zahl())
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(titel)
                .font(.system(size: 12, weight: .semibold))
            Text(hinweis)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }

    // MARK: Verlauf

    @ViewBuilder
    private var verlauf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DIESE SITZUNG")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            if state.verlauf.isEmpty {
                leer
            } else {
                VStack(spacing: 0) {
                    ForEach(state.verlauf) { d in
                        zeile(d)
                        if d.id != state.verlauf.last?.id {
                            Divider().padding(.leading, 84)
                        }
                    }
                }
                .ekkoKarte(innen: 0)
                Text("Klick auf ein Diktat kopiert es. Der Verlauf lebt nur, solange Ekko läuft.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func zeile(_ d: Diktat) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(d.text, forType: .string)
            withAnimation(.easeOut(duration: 0.15)) { kopiert = d.id }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(d.zeit, format: .dateTime.hour().minute())
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                appIcon(d.app)
                Text(d.text)
                    .font(.system(size: 13.5))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: kopiert == d.id ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(kopiert == d.id
                        ? EkkoFarbe.akzent : Color.secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: kopiert == d.id)
                    .opacity(ueber == d.id || kopiert == d.id ? 1 : 0.5)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(ueber == d.id ? Color.primary.opacity(0.045) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { drin in
            withAnimation(.easeOut(duration: 0.12)) { ueber = drin ? d.id : nil }
        }
    }

    /// Icon der App, in die diktiert wurde (unbekannt → neutrales Symbol).
    @ViewBuilder
    private func appIcon(_ bundleId: String?) -> some View {
        if let bundleId, let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 18, height: 18)
                .help(FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: ""))
        } else {
            Image(systemName: "text.cursor")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 18, height: 18)
        }
    }

    private var leer: some View {
        VStack(spacing: 12) {
            ImpulsZeichen(groesse: 40)
            Text("Noch keine Diktate in dieser Sitzung")
                .font(.system(size: 14, weight: .semibold))
            HotkeyHinweis(hotkey: state.hotkey, rest: "halten, sprechen, loslassen.",
                          groesse: 12)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .ekkoKarte(innen: 0)
    }
}
