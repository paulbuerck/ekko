import Foundation
import WhisperKit

/// Streaming-Bench: misst Streaming-Machbarkeit auf echter Hardware.
/// Simuliert Echtzeit — der Puffer wächst mit der Wanduhr, jeder Pass
/// transkribiert den Stand wie AudioStreamTranscriber (clipTimestamps ab
/// letztem bestätigtem Segment, Confirm bei >2 Segmenten). Kein Mikro,
/// deterministisch wiederholbar.
enum StreamBench {
    static func lauf(clip: URL, modell: String, maxSekunden: Double) async {
        setvbuf(stdout, nil, _IONBF, 0)
        print("== WhisperKit-StreamBench ==")
        print("Clip:   \(clip.lastPathComponent)")
        print("Modell: \(modell)  ·  Limit: \(Int(maxSekunden)) s")
        let ramVorher = residentSpeicherMB()

        do {
            let t0 = Date()
            let pipe = try await WhisperKit(WhisperKitConfig(model: modell))
            print(String(format: "Modell geladen in %.1f s  ·  RAM %.0f MB (Modell ~%.0f MB)",
                         Date().timeIntervalSince(t0), residentSpeicherMB(),
                         residentSpeicherMB() - ramVorher))

            let alleSamples = try AudioProcessor.loadAudioAsFloatArray(
                fromPath: clip.path)
            let rate = Double(WhisperKit.sampleRate)
            let audioDauer = min(Double(alleSamples.count) / rate, maxSekunden)
            print(String(format: "Audio: %.0f s (von %.0f s)", audioDauer,
                         Double(alleSamples.count) / rate))

            var options = DecodingOptions()
            options.task = .transcribe
            options.language = nil  // Auto — wie die App

            var bestaetigt: [TranscriptionSegment] = []
            var bestaetigtEnde: Float = 0
            var letzterPufferStand = 0
            var passLatenzen: [Double] = []
            var maxLag = 0.0
            var ramPeak = residentSpeicherMB()

            let start = Date()
            while true {
                let vergangen = Date().timeIntervalSince(start)
                if vergangen >= audioDauer { break }
                let stand = min(Int(vergangen * rate), alleSamples.count)
                // wie AudioStreamTranscriber: erst ab 1 s neuem Audio rechnen
                if Double(stand - letzterPufferStand) / rate < 1 {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    continue
                }
                letzterPufferStand = stand

                var opts = options
                opts.clipTimestamps = [bestaetigtEnde]
                let p0 = Date()
                let ergebnis = try await pipe.transcribe(
                    audioArray: Array(alleSamples[0..<stand]),
                    decodeOptions: opts)
                let latenz = Date().timeIntervalSince(p0)
                passLatenzen.append(latenz)

                let segmente = ergebnis.flatMap(\.segments)
                if segmente.count > 2 {  // requiredSegmentsForConfirmation
                    let neu = segmente.prefix(segmente.count - 2)
                    if let ende = neu.last?.end, ende > bestaetigtEnde {
                        bestaetigtEnde = ende
                        bestaetigt.append(contentsOf: neu)
                    }
                }
                let pufferS = Double(stand) / rate
                let lag = pufferS - Double(bestaetigtEnde)
                maxLag = max(maxLag, lag)
                ramPeak = max(ramPeak, residentSpeicherMB())
                print(String(format:
                    "Pass %2d  Puffer %5.1f s  Latenz %5.2f s  bestätigt bis %5.1f s  Lag %5.1f s  RAM %4.0f MB  %@",
                    passLatenzen.count, pufferS, latenz, Double(bestaetigtEnde),
                    lag, residentSpeicherMB(), thermik()))
            }

            let rechenzeit = passLatenzen.reduce(0, +)
            print("== Zusammenfassung ==")
            print(String(format: "Pässe: %d  ·  Latenz mean %.2f s / max %.2f s",
                         passLatenzen.count,
                         rechenzeit / Double(max(passLatenzen.count, 1)),
                         passLatenzen.max() ?? 0))
            print(String(format: "Rechenzeit %.1f s auf %.0f s Audio → Auslastung %.0f %%",
                         rechenzeit, audioDauer, 100 * rechenzeit / audioDauer))
            print(String(format: "max Lag (Puffer − bestätigt): %.1f s", maxLag))
            print(String(format: "RAM-Peak: %.0f MB  ·  Thermik am Ende: %@",
                         ramPeak, thermik()))
            let text = bestaetigt.map(\.text).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            print("Bestätigter Text (Anfang): \(String(text.prefix(300)))")
            print("== fertig ==")
        } catch {
            print("StreamBench-Fehler: \(error)")
        }
    }

    private static func thermik() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "thermisch: nominal"
        case .fair: return "thermisch: fair"
        case .serious: return "thermisch: SERIOUS"
        case .critical: return "thermisch: CRITICAL"
        @unknown default: return "thermisch: ?"
        }
    }
}
