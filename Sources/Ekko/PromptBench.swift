import Foundation
import WhisperKit

/// Biasing-Messung: dieselben Clips ohne und mit Wörterbuch-Prompt
/// (`promptTokens`) transkribieren, Text + Zeit je Lauf. Reiner CLI-Pfad.
/// Ekko --bench-prompt <modell> "<Wort, Wort>" <clip>...
/// Sprache fest Deutsch, damit nur der Prompt-Effekt gemessen wird.
/// Befund 2026-10-22 (WhisperKit 0.14.1, large-v3-turbo 632 MB): mit
/// Prompt bricht der Decoder sofort ab (leerer Text) — Biasing deshalb
/// nicht in der App. Nach WhisperKit-Updates hiermit erneut prüfen.
enum PromptBench {
    static func lauf(modell: String, woerter: [String], clips: [URL]) async {
        setvbuf(stdout, nil, _IONBF, 0)
        do {
            let pipe = try await WhisperKit(WhisperKitConfig(model: modell))
            var prompt: [Int]?
            for clip in clips {
                // Warmlauf (lädt auch den Tokenizer), Zeiten vergleichbar
                _ = try await pipe.transcribe(audioPath: clip.path)
                if prompt == nil {
                    prompt = WhisperTranscriber.promptTokens(woerter, pipe: pipe)
                    print("Prompt-Tokens: \(prompt?.count ?? 0)")
                }
                for (name, tokens) in [("ohne", nil), ("mit ", prompt)] {
                    var options = DecodingOptions()
                    options.task = .transcribe
                    options.language = "de"
                    options.promptTokens = tokens
                    options.skipSpecialTokens = true
                    let t0 = Date()
                    let text = try await pipe.transcribe(
                        audioPath: clip.path, decodeOptions: options)
                        .map(\.text).joined()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    print(String(format: "%@ | %@ | %.2f s | %@",
                                 clip.lastPathComponent, name,
                                 Date().timeIntervalSince(t0), text))
                }
            }
        } catch {
            print("Bench-Fehler: \(error)")
        }
    }
}
