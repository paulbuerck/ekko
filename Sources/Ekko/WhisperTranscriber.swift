import Foundation
import AVFoundation
import WhisperKit

/// STT über WhisperKit (small, on-device CoreML/ANE), Auto-Spracherkennung.
/// Ersetzt den Apple-`Transcriber` im App-Fluss.
///
/// @MainActor für die Puffer-Annahme (AVAudioPCMBuffer ist nicht Sendable);
/// die eigentlichen WhisperKit-Aufrufe laufen `nonisolated` (off-MainActor),
/// weil WhisperKit seine Nebenläufigkeit selbst managt.
@MainActor
final class WhisperTranscriber {
    enum Fehler: LocalizedError {
        case nichtBereit
        var errorDescription: String? { String(localized: "STT-Modell nicht bereit") }
    }

    // large-v3-turbo (quantisiert 632 MB): Auto-Spracherkennung zuverlässig
    // (small versagte), warm ~0,8 s, ~100 MB working. Erst-Start kompiliert
    // das ANE-Modell einmalig (~5 min, danach gecacht) — Prewarm fängt's ab.
    private let modell = "openai_whisper-large-v3-v20240930_turbo_632MB"
    nonisolated(unsafe) private var pipe: WhisperKit?

    /// Biasing: Wörterbuch-Zielwörter als Decoder-Prompt (Fachwörter schon bei
    /// der Erkennung richtig). Ohne Sonder-Tokens, sonst bricht der Decoder.
    nonisolated static func promptTokens(_ woerter: [String],
                                         pipe: WhisperKit) -> [Int]? {
        guard !woerter.isEmpty, let tok = pipe.tokenizer else { return nil }
        let ids = tok.encode(text: " " + woerter.joined(separator: ", "))
            .filter { $0 < tok.specialTokens.specialTokenBegin }
        return ids.isEmpty ? nil : ids
    }

    /// Lädt das Modell und prewarmt (Dummy-Inferenz kompiliert das ANE-Modell
    /// einmalig ~45 s), damit das erste echte Diktat warm ist.
    nonisolated func prepare() async throws {
        let config = WhisperKitConfig(model: modell)
        pipe = try await WhisperKit(config)
        let warm = FileManager.default.temporaryDirectory
            .appendingPathComponent("ekko-prewarm-\(UUID().uuidString).wav")
        try? schreibeTon(nach: warm, sekunden: 1.0)
        _ = try? await transcribeFile(warm)
        try? FileManager.default.removeItem(at: warm)
    }

    /// Übersetzen-Schalter (Einstellungen, Default aus) — .translate
    /// übersetzt alles nach Englisch, sonst gleiche Sprache.
    nonisolated static var task: DecodingTask {
        UserDefaults.standard.bool(forKey: "uebersetzen")
            ? .translate : .transcribe
    }

    nonisolated func transcribeFile(_ url: URL) async throws -> String {
        guard let pipe else { throw Fehler.nichtBereit }
        var options = DecodingOptions()
        options.task = Self.task
        options.language = nil       // automatische Spracherkennung (mehrsprachig)
        let results = try await pipe.transcribe(
            audioPath: url.path, decodeOptions: options)
        return results.map(\.text).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Puffer → Temp-WAV → transkribieren (gleicher Weg wie beim Apple-Engine,
    /// minimaler Eingriff).
    func transcribe(_ buffer: AVAudioPCMBuffer) async throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ekko-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let file = try AVAudioFile(
                forWriting: url, settings: buffer.format.settings)
            try file.write(from: buffer)
        }
        return try await transcribeFile(url)
    }

    /// Kurzer 440-Hz-Ton (NICHT Stille): WhisperKit überspringt bei Stille
    /// die volle Inferenz — dann kompiliert das ANE-Modell erst beim ersten
    /// echten Diktat (~1-2 min). Mit Ton läuft der volle Pfad schon im Prewarm.
    nonisolated private func schreibeTon(nach url: URL,
                                         sekunden: Double) throws {
        let sr = 16000.0
        guard let fmt = AVAudioFormat(
            standardFormatWithSampleRate: sr, channels: 1),
            let buf = AVAudioPCMBuffer(
                pcmFormat: fmt,
                frameCapacity: AVAudioFrameCount(sr * sekunden))
        else { return }
        buf.frameLength = buf.frameCapacity
        if let ch = buf.floatChannelData?[0] {
            for i in 0..<Int(buf.frameLength) {
                ch[i] = 0.2 * sinf(Float(2.0 * .pi * 440.0 * Double(i) / sr))
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        try file.write(from: buf)
    }
}

extension WhisperTranscriber: Transkribierer {
    nonisolated func transkribiere(_ audio: URL) async throws -> String {
        try await transcribeFile(audio)
    }
}

// MARK: - Live-Streaming

/// Steuerung des Streaming-Loops von außen (Main → Hintergrund-Task).
/// Lock-geschützt statt Actor, damit der Loop ohne await-Hops pollen kann.
final class LiveSteuerung: @unchecked Sendable {
    private let lock = NSLock()
    private var _fertig = false
    private var _abgebrochen = false

    var fertig: Bool {
        lock.lock(); defer { lock.unlock() }; return _fertig
    }
    var abgebrochen: Bool {
        lock.lock(); defer { lock.unlock() }; return _abgebrochen
    }
    /// Loslassen: Loop macht den Abschluss-Pass und liefert den Finaltext.
    func beende() {
        lock.lock(); _fertig = true; lock.unlock()
    }
    /// Esc: Loop bricht sofort ab, kein Ergebnis.
    func brichAb() {
        lock.lock(); _abgebrochen = true; lock.unlock()
    }
}

extension WhisperTranscriber {
    struct LiveStand: Sendable {
        let bestaetigt: String
        let hypothese: String
    }

    /// Streaming-Diktat: transkribiert den wachsenden Puffer wie der
    /// Streaming-Bench (clipTimestamps ab letzter Konfirmation, Confirm-Fenster 2),
    /// meldet jeden Stand über `onUpdate` und liefert nach `beende()`
    /// den finalen Text (letzter Pass über den vollen Puffer — kein
    /// zweiter Voll-Durchlauf). `brichAb()` → nil.
    nonisolated func streame(
        samples: @escaping @Sendable () -> [Float],
        steuerung: LiveSteuerung,
        onUpdate: @escaping @Sendable (LiveStand) -> Void
    ) async throws -> String? {
        guard let pipe else { throw Fehler.nichtBereit }
        var options = DecodingOptions()
        options.task = Self.task
        options.language = nil

        var konf = LiveKonfirmation()
        var letzterStand = 0

        func pass(_ audio: [Float]) async throws -> [LiveSegment] {
            var opts = options
            opts.clipTimestamps = [konf.bestaetigtEnde]
            let ergebnis = try await pipe.transcribe(
                audioArray: audio, decodeOptions: opts)
            return ergebnis.flatMap(\.segments).map {
                // segment.text ist roh und enthält Special-Tokens
                // (<|startoftranscript|>, Zeitstempel) — anders als
                // result.text. Strippen, sonst landen sie im Paste.
                LiveSegment(
                    text: $0.text.replacingOccurrences(
                        of: #"<\|[^|]*\|>"#, with: "",
                        options: .regularExpression),
                    ende: $0.end)
            }
        }

        while !steuerung.fertig && !steuerung.abgebrochen {
            let audio = samples()
            // wie AudioStreamTranscriber: erst ab ~1 s neuem Audio rechnen
            if audio.count - letzterStand < 16_000 {
                try await Task.sleep(nanoseconds: 100_000_000)
                continue
            }
            letzterStand = audio.count
            konf.nimm(try await pass(audio))
            onUpdate(LiveStand(bestaetigt: konf.bestaetigterText,
                               hypothese: konf.hypothesenText))
        }
        if steuerung.abgebrochen { return nil }

        // Abschluss-Pass: alles seit letzter Konfirmation wird fest.
        let rest = samples()
        if rest.count - letzterStand > 1600 {  // >0,1 s Neues
            konf.schliesseAb(mit: try await pass(rest))
        } else {
            konf.schliesseAb(mit: [])
        }
        return konf.bestaetigterText
    }
}
