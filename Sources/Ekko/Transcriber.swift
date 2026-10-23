import AVFoundation
import Speech

@MainActor
protocol Transkribierer {
    func transkribiere(_ audio: URL) async throws -> String
}

/// STT über Apples SpeechAnalyzer (macOS 26, on-device).
/// Sprachpaket wird beim ersten Start einmalig installiert; danach
/// läuft alles offline.
/// @MainActor: vermeidet Region-Transfers der (nicht Sendable-)
/// Audio-Puffer; alle Wartezeiten sind awaits, blockieren also nichts.
@MainActor
final class Transcriber {
    private let locale = Locale(identifier: "de-DE")

    /// Stellt sicher, dass das Sprachmodell lokal installiert ist.
    func prepare() async throws {
        let installed = await SpeechTranscriber.installedLocales
        print("Installierte STT-Locales: \(installed.map(\.identifier))")
        if installed.contains(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) {
            return  // Sprachpaket da — Download-Pfad gar nicht betreten
        }
        let transcriber = SpeechTranscriber(
            locale: locale, preset: .transcription)
        print("Fordere Sprachpaket an…")
        if let request = try await AssetInventory
            .assetInstallationRequest(supporting: [transcriber]) {
            print("Lade Sprachpaket…")
            try await request.downloadAndInstall()
        }
        print("Sprachpaket installiert.")
    }

    /// Transkribiert eine Audio-Datei (de-DE). Apple-Engine, im App-Fluss
    /// durch WhisperTranscriber ersetzt — bleibt für CLI/Revert.
    func transcribeFile(_ url: URL) async throws -> String {
        let transcriber = SpeechTranscriber(
            locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)
        // Results nebenläufig sammeln — der Stream endet erst nach
        // finalize, sequenzielles Warten wäre Deadlock:
        let results = Task {
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
            }
            return text
        }
        _ = try await analyzer.analyzeSequence(from: file)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = try await results.value
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Transkribiert einen Puffer über den Datei-Pfad (der Stream-Pfad
    /// mit rohem Puffer trapt im Speech-Framework, Crash 2026-07-03;
    /// Datei-Pfad ist bench-bewiesen, Schreibkosten ~ms).
    func transcribe(_ buffer: AVAudioPCMBuffer) async throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ekko-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        do {  // eigener Scope: AVAudioFile schließt beim Verlassen
            let file = try AVAudioFile(
                forWriting: url, settings: buffer.format.settings)
            try file.write(from: buffer)
        }
        return try await transcribeFile(url)
    }
}

extension Transcriber: Transkribierer {
    func transkribiere(_ audio: URL) async throws -> String {
        try await transcribeFile(audio)
    }
}
