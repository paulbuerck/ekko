// Sources/Ekko/TranskriptionsQueue.swift
import Foundation

@MainActor
final class TranskriptionsQueue: ObservableObject {
    enum Quelle { case datei(URL); case web(URL)
        var url: URL { switch self { case .datei(let u), .web(let u): return u } }
    }
    enum Zustand: Equatable {
        case wartet, laedt(Double), transkribiert(Double)
        case fertig(URL), fehler(String)
    }
    struct Item: Identifiable {
        let id = UUID()
        var quelle: Quelle
        var zustand: Zustand = .wartet
        var name: String { quelle.url.lastPathComponent }
    }

    @Published private(set) var items: [Item] = []
    var pausiert = false
    private var laeuft = false

    private let transkribierer: Transkribierer
    private let woerterbuch: Woerterbuch
    private let aufTranskript: (URL, String) -> Void

    init(transkribierer: Transkribierer, woerterbuch: Woerterbuch,
         aufTranskript: @escaping (URL, String) -> Void) {
        self.transkribierer = transkribierer
        self.woerterbuch = woerterbuch
        self.aufTranskript = aufTranskript
    }

    func fuegeDateiHinzu(_ url: URL) {
        items.append(Item(quelle: .datei(url)))
        Task { await verarbeiteNaechstes() }
    }

    func fuegeWebHinzu(_ url: URL) {
        items.append(Item(quelle: .web(url)))
        Task { await verarbeiteNaechstes() }
    }

    func retry(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].zustand = .wartet
        Task { await verarbeiteNaechstes() }
    }

    func verarbeiteNaechstes() async {
        guard !laeuft else { return }
        laeuft = true
        defer { laeuft = false }
        // Schleife statt Rekursion: laeuft bleibt für die ganze
        // Warteschlange gesetzt, sonst würde der Reentrancy-Schutz den
        // rekursiven "nächstes Item"-Aufruf sofort wieder abweisen.
        while !pausiert,
              let idx = items.firstIndex(where: { $0.zustand == .wartet }) {
            do {
                let quellAudio: URL
                var webTitel: String?
                switch items[idx].quelle {
                case .datei(let u):
                    quellAudio = u
                case .web(let u):
                    items[idx].zustand = .laedt(0)
                    let ergebnis = try await Downloader.lade(u)
                    quellAudio = ergebnis.audio
                    webTitel = ergebnis.titel
                }
                items[idx].zustand = .transkribiert(0)
                let audio = try await MediaExtractor.audioURL(for: quellAudio)
                let roh = try await transkribierer.transkribiere(audio)
                let text = woerterbuch.apply(roh)
                let ziel = try TranskriptAblage.schreibe(
                    quelle: items[idx].quelle.url, text: text,
                    anzeigeName: webTitel)
                // Temp-Audio erst NACH erfolgreicher Ablage löschen —
                // wirft schreibe (Platte voll, Rechte), wären sonst Text
                // UND Audio weg (Fehlerklasse des Meeting-Vorfalls).
                // audio != quellAudio: MediaExtractor hat neu extrahiert ->
                // immer ein Temp-File, nie die Quelle des Nutzers.
                if audio != quellAudio {
                    try? FileManager.default.removeItem(at: audio)
                }
                // quellAudio selbst ist bei .web ein heruntergeladenes
                // Temp-File (nie die Quelle des Nutzers) und muss so oder
                // so weg — auch wenn es unverändert weiterverwendet wurde.
                if case .web = items[idx].quelle {
                    try? FileManager.default.removeItem(at: quellAudio)
                }
                items[idx].zustand = .fertig(ziel)
                aufTranskript(ziel, text)
            } catch {
                items[idx].zustand = .fehler(error.localizedDescription)
            }
        }
    }
}
