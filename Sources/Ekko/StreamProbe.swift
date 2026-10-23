import Foundation
import WhisperKit

/// Headless-Verify des Live-Text-Pfads: nutzt WhisperTranscriber.streame
/// (die echte App-Route inkl. LiveKonfirmation und Abschluss-Pass) mit
/// Datei-Audio in simulierter Echtzeit statt Mikro. Beweist Loop,
/// Live-Stände und Finaltext ohne Sprechen.
/// Threadsicherer Zähler — onUpdate ist @Sendable, eine captured var
/// wäre dort ein Compile-Fehler.
private final class Zaehler: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func naechster() -> Int {
        lock.lock(); defer { lock.unlock() }
        n += 1
        return n
    }
    var wert: Int {
        lock.lock(); defer { lock.unlock() }
        return n
    }
}

enum StreamProbe {
    @MainActor
    static func lauf(clip: URL, sekunden: Double) async {
        print("== StreamProbe (Live-Text-Pfad headless) ==")
        let transcriber = WhisperTranscriber()
        do {
            print("Modell lädt/prewarmt…")
            try await transcriber.prepare()

            let alle = try AudioProcessor.loadAudioAsFloatArray(
                fromPath: clip.path)
            let rate = Double(WhisperKit.sampleRate)
            let dauer = min(Double(alle.count) / rate, sekunden)
            print(String(format: "Audio: %.0f s · Clip %@", dauer,
                         clip.lastPathComponent))

            let start = Date()
            let steuerung = LiveSteuerung()
            // „Mikro": liefert so viele Samples, wie Wanduhr-Zeit vergangen ist
            let samples: @Sendable () -> [Float] = {
                let n = min(Int(Date().timeIntervalSince(start) * rate),
                            alle.count)
                return Array(alle[0..<n])
            }
            // Loslassen nach `dauer` Sekunden simulieren:
            Task {
                try? await Task.sleep(
                    nanoseconds: UInt64(dauer * 1_000_000_000))
                steuerung.beende()
            }
            let staende = Zaehler()
            let finaltext = try await transcriber.streame(
                samples: samples, steuerung: steuerung,
                onUpdate: { stand in
                    let n = staende.naechster()
                    let fest = stand.bestaetigt.suffix(50)
                    let hyp = stand.hypothese.prefix(40)
                    print("Stand \(n): …\(fest) ⌁ \(hyp)…")
                })
            guard let finaltext else {
                print("FEHLER: abgebrochen ohne Abbruch-Befehl")
                exit(1)
            }
            print(String(format: "Latenz Loslassen → Finaltext: %.2f s",
                         Date().timeIntervalSince(start) - dauer))
            print("== Finaltext (\(finaltext.count) Zeichen) ==")
            print(finaltext)
            print(staende.wert >= 2 && !finaltext.isEmpty
                  ? "== PROBE GRÜN ==" : "== PROBE ROT ==")
        } catch {
            print("StreamProbe-Fehler: \(error)")
            exit(1)
        }
    }
}
