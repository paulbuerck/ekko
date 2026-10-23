import AVFoundation

/// Meeting-Aufnahme: Mikro inkrementell in eine WAV-Datei.
/// Kein RAM-Puffer — bei Absturz bleibt die Datei bis dahin gültig.
final class MeetingRecorder {
    private var engine = AVAudioEngine()
    private var datei: AVAudioFile?
    private(set) var laeuft = false

    func start() throws -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Diktate")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmm"
        let url = dir.appendingPathComponent(
            "\(df.string(from: Date()))-meeting.wav")
        // Frische Engine pro Aufnahme: eine wiederverwendete Engine hält
        // nach Geräte-/Formatwechsel ein stales Input-Format — installTap
        // wirft dann eine NSException („format mismatch"), die Swift-catch
        // nie sieht und AppKit still schluckt (Befund 2026-07-09).
        engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(
                domain: "de.paul.ekko", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Mikrofon liefert kein gültiges Format (\(format))"])
        }
        datei = try AVAudioFile(forWriting: url, settings: format.settings)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) {
            [weak self] buffer, _ in
            try? self?.datei?.write(from: buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // halbe Aufnahme nicht liegen lassen: Tap + Header-Datei weg
            input.removeTap(onBus: 0)
            datei = nil
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        laeuft = true
        return url
    }

    func stop() -> URL? {
        guard laeuft else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        laeuft = false
        let url = datei?.url
        datei = nil  // schließt Datei
        return url
    }
}
