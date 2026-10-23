// Sources/Ekko/Panes/ImportPane.swift
import SwiftUI
import UniformTypeIdentifiers

struct ImportPane: View {
    @EnvironmentObject var queue: TranskriptionsQueue
    @State private var link = ""

    @State private var ziehtDrueber = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SeitenKopf(
                titel: String(localized: "Import"),
                untertitel: String(localized: "Video- und Audiodateien oder Links transkribieren — läuft lokal, Ergebnis landet in Transkripte."))
            ablage
            eingabe
            warteschlange
        }
        .ekkoSeite()
    }

    private var ablage: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(EkkoFarbe.akzent)
            Text("Datei hierher ziehen")
                .font(.system(size: 14, weight: .semibold))
            Text("MP4, MOV, MP3, WAV, M4A …")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(ziehtDrueber ? EkkoFarbe.akzentWeich : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(EkkoFarbe.akzent.opacity(ziehtDrueber ? 0.9 : 0.45),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
        .animation(.easeOut(duration: 0.15), value: ziehtDrueber)
        .onDrop(of: [.fileURL], isTargeted: $ziehtDrueber) { anbieter in
            for a in anbieter {
                _ = a.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in
                        queue.fuegeDateiHinzu(url) } }
                }
            }
            return true
        }
    }

    private var eingabe: some View {
        HStack(spacing: 10) {
            Button { waehle() } label: {
                Label("Datei wählen…", systemImage: "folder")
            }
            Divider().frame(height: 20)
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            TextField(Downloader.vorhanden
                ? "Link einfügen (YouTube, Instagram …)"
                : "yt-dlp fehlt — brew install yt-dlp", text: $link)
                .textFieldStyle(.plain)
                .disabled(!Downloader.vorhanden)
                .onSubmit(laden)
            Button("Laden", action: laden)
                .buttonStyle(.glassProminent)
                .tint(EkkoFarbe.akzent)
                .disabled(!Downloader.vorhanden || link.isEmpty)
        }
        .ekkoKarte(innen: 12)
    }

    @ViewBuilder
    private var warteschlange: some View {
        if !queue.items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("WARTESCHLANGE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(queue.items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(EkkoFarbe.akzent)
                                .frame(width: 26, height: 26)
                                .background(EkkoFarbe.akzentWeich,
                                    in: RoundedRectangle(cornerRadius: EkkoMetrik.kachelRadius))
                            Text(item.name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                            Spacer()
                            zustandsAnsicht(item)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        if item.id != queue.items.last?.id { Divider() }
                    }
                }
                .ekkoKarte(innen: 0)
            }
        }
    }

    private func laden() {
        if let url = URL(string: link), Downloader.vorhanden, !link.isEmpty {
            queue.fuegeWebHinzu(url); link = ""
        }
    }

    @ViewBuilder private func zustandsAnsicht(_ item: TranskriptionsQueue.Item) -> some View {
        switch item.zustand {
        case .wartet: statusPille("wartet", .secondary)
        case .laedt(let p): statusPille("lädt \(Int(p*100)) %", EkkoFarbe.akzent)
        case .transkribiert:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                statusPille("transkribiert", EkkoFarbe.akzent)
            }
        case .fertig(let url):
            Button("→ Transkript") {
                NSWorkspace.shared.activateFileViewerSelecting([url]) }
            .tint(EkkoFarbe.akzent)
            .foregroundStyle(EkkoFarbe.akzent)
        case .fehler(let m):
            HStack {
                Text(m).font(.caption).foregroundStyle(.red).lineLimit(1)
                Button { queue.retry(item.id) } label: {
                    Image(systemName: "arrow.clockwise") }
            }
        }
    }

    private func statusPille(_ text: LocalizedStringKey, _ farbe: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(farbe.opacity(0.12), in: Capsule())
            .foregroundStyle(farbe)
    }

    private func waehle() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.movie, .audio, .mpeg4Movie,
                                 .quickTimeMovie, .wav, .mp3, .mpeg4Audio]
        p.allowsMultipleSelection = true
        if p.runModal() == .OK { p.urls.forEach { queue.fuegeDateiHinzu($0) } }
    }
}
