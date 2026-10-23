// Sources/Ekko/Panes/StilPane.swift
import SwiftUI
import AppKit

/// Stil-Profile als eigener Bereich: welche App
/// welchen Diktat-Ton bekommt. Logik unverändert aus den Einstellungen.
struct StilPane: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var profile = ProfilStore.shared
    @State private var neuProfilApp = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SeitenKopf(
                titel: String(localized: "Stil"),
                untertitel: String(localized: "Ekko passt den Ton an die App an, in die du diktierst — förmlich in Mail, knapp im Chat, roh im Code."))
            if !state.cleanupAn {
                Label("Stil-Profile greifen nur mit eingeschaltetem Cleanup (Einstellungen).",
                      systemImage: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(EkkoFarbe.meeting)
                    .ekkoKarte(innen: 12)
            }
            VStack(spacing: 0) {
                ForEach($profile.zuordnungen) { $z in
                    zeile($z)
                    Divider()
                }
                neueZeile
            }
            .ekkoKarte(innen: 0)
            Text("Unbekannte Apps bekommen das Standard-Putzen.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .ekkoSeite()
    }

    private func zeile(_ z: Binding<ProfilZuordnung>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                appIcon(z.wrappedValue.bundleId)
                Text(appName(z.wrappedValue.bundleId))
                    .font(.system(size: 13.5, weight: .medium))
                Spacer()
                Picker("", selection: z.art) {
                    ForEach(StilArt.allCases) { art in
                        Text(art.label).tag(art)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
                Button(role: .destructive) {
                    profile.zuordnungen.removeAll {
                        $0.bundleId == z.wrappedValue.bundleId
                    }
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Profil entfernen")
            }
            TextField(
                "Eigener Prompt (leer = Standard von »\(z.wrappedValue.art.label)«)",
                text: eigenerPromptBinding(z), axis: .vertical)
                .font(.system(size: 12))
                .textFieldStyle(.roundedBorder)
                .padding(.leading, 34)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var neueZeile: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(EkkoFarbe.akzent)
                .frame(width: 22)
            Picker("", selection: $neuProfilApp) {
                Text("App hinzufügen…").tag("")
                ForEach(profilKandidaten, id: \.id) { k in
                    Text(k.name).tag(k.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
            Spacer()
            Button("Hinzufügen") {
                guard !neuProfilApp.isEmpty else { return }
                profile.zuordnungen.append(
                    .init(bundleId: neuProfilApp, art: .standard))
                neuProfilApp = ""
            }
            .buttonStyle(.glassProminent)
            .tint(EkkoFarbe.akzent)
            .disabled(neuProfilApp.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func appIcon(_ bundleId: String) -> some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleId) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: "app.dashed").resizable()
            }
        }
        .frame(width: 22, height: 22)
    }

    private func appName(_ bundleId: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleId) else { return bundleId }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    /// Laufende reguläre Apps ohne bestehende Zuordnung.
    private var profilKandidaten: [(id: String, name: String)] {
        let vergeben = Set(profile.zuordnungen.map(\.bundleId))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier,
                      id != Bundle.main.bundleIdentifier,
                      !vergeben.contains(id) else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name < $1.name }
    }

    private func eigenerPromptBinding(
        _ z: Binding<ProfilZuordnung>) -> Binding<String> {
        Binding(
            get: { z.wrappedValue.eigenerPrompt ?? "" },
            set: { neu in
                let getrimmt = neu.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                z.wrappedValue.eigenerPrompt =
                    getrimmt.isEmpty ? nil : neu
            })
    }
}
