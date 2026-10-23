import Foundation
import WhisperKit

/// Misst WhisperKit auf echter Hardware: RAM (vor/nach Modell-Load),
/// Latenz je Lauf, druckt Transkript. Reiner CLI-Messpfad.
enum WhisperBench {
    /// `sprache` nil = Auto-Erkennung, sonst "de"/"en" erzwungen.
    static func lauf(clip: URL, modell: String, laeufe: Int,
                     sprache: String?) async {
        setvbuf(stdout, nil, _IONBF, 0)
        print("== WhisperKit-Bench ==")
        print("Clip:    \(clip.lastPathComponent)")
        print("Modell:  \(modell)")
        print("Sprache: \(sprache ?? "auto")")
        let ramVorher = residentSpeicherMB()
        print(String(format: "RAM vor Modell-Load: %.0f MB", ramVorher))

        do {
            let t0 = Date()
            let config = WhisperKitConfig(model: modell)
            let pipe = try await WhisperKit(config)
            let ladeZeit = Date().timeIntervalSince(t0)
            let ramNachher = residentSpeicherMB()
            print(String(format: "Modell geladen in %.1f s", ladeZeit))
            print(String(format: "RAM nach Load: %.0f MB  (Modell ~%.0f MB)",
                         ramNachher, ramNachher - ramVorher))

            var options = DecodingOptions()
            options.task = .transcribe  // wie die App: nie übersetzen
            options.language = sprache  // nil = Auto-Erkennung

            for i in 1...laeufe {
                let s0 = Date()
                let results = try await pipe.transcribe(
                    audioPath: clip.path, decodeOptions: options)
                let dt = Date().timeIntervalSince(s0)
                let text = results.map(\.text).joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                print(String(format: "Lauf %d: %.2f s  RAM %.0f MB",
                             i, dt, residentSpeicherMB()))
                if i == laeufe { print("Transkript: \(text)") }
            }
            print("== fertig ==")
        } catch {
            print("Bench-Fehler: \(error)")
        }
    }
}
