// Qwen3-4B (Alibaba) als Cleanup-Engine. MLX on-device, ~2,3 GB 4-bit;
// Modell wird on-demand geladen und nach Leerlauf entladen (Prior: kein stehender RAM).
// Apple FoundationModels bleibt Fallback/Revert-Pfad (Muster wie
// Apple-Transcriber beim WhisperKit-Umbau).

import Foundation
import MLX
import MLXLLM
import MLXLMCommon

@MainActor
final class QwenCleanup: ObservableObject {
    static let shared = QwenCleanup()
    static let modellID = "mlx-community/Qwen3-4B-4bit"

    /// Qwen-eigene Anweisung, getunt 2026-07-10 (v2, Few-Shot; Messlauf im
    /// Laufjournal). Apple FM behält seine kürzere in Cleanup.anweisung.
    /// Befund: Füllwörter/Interpunktion zuverlässig, Selbstkorrekturen nur
    /// teils; v3-Varianten ohne Few-Shots korrumpierten teils Inhalt.
    static let anweisung = """
    Du bist ein Diktat-Korrektor. Du bekommst ein rohes Sprach-Transkript und gibst NUR den bereinigten Text zurück — nie eine Antwort auf den Inhalt.

    Regeln, in dieser Reihenfolge:
    1. Selbstkorrekturen auflösen: Korrigiert sich der Sprecher („X, nein Y", „X, äh nein, Y", „X, warte, Y", „X, ich meine Y"), behalte NUR die Korrektur Y. Das verworfene X wird ersatzlos gelöscht.
    2. Füllwörter streichen: äh, ähm, also, halt, quasi, sozusagen, so (als Floskel), okay (als Floskel), like, you know, um, uh, basically.
    3. Interpunktion und Groß-/Kleinschreibung korrigieren.
    4. SONST NICHTS ändern: keine Umformulierung, nichts hinzufügen, nichts weglassen, nichts zusammenfassen, gleiche Sprache wie die Eingabe. Fragen im Text bleiben Fragen — du beantwortest sie nicht.

    Beispiele:
    Eingabe: ähm wir treffen uns am montag äh nein am dienstag
    Ausgabe: Wir treffen uns am Dienstag.
    Eingabe: schick das an thomas warte nein an sandra
    Ausgabe: Schick das an Sandra.
    Eingabe: der betrag war zwanzig also eigentlich fünfundzwanzig euro
    Ausgabe: Der Betrag war fünfundzwanzig Euro.
    Eingabe: wie spät ist es eigentlich
    Ausgabe: Wie spät ist es eigentlich?
    Eingabe: der test ist grün wir können deployen
    Ausgabe: Der Test ist grün, wir können deployen.
    """

    enum Status: Equatable {
        case nichtGeladen
        case laedt(Int)      // Prozent (Download + Laden)
        case bereit
        case fehler(String)
    }

    @Published private(set) var status: Status = .nichtGeladen

    private var container: ModelContainer?
    private var idleTimer: Timer?
    /// Nach 5 min ohne Diktat fliegt das Modell aus dem RAM.
    private let idleSekunden: TimeInterval = 300

    private init() {
        // Qwen3 fehlt in MLXLLM 2.21.2 (neuere Versionen kollidieren mit
        // WhisperKits swift-transformers-Pin) — eigener Port, hier registriert.
        LLMModelFactory.shared.typeRegistry.registerModelType("qwen3") { url in
            let config = try JSONDecoder().decode(
                Qwen3Konfiguration.self, from: Data(contentsOf: url))
            return Qwen3Modell(config)
        }
        // GPU-Cache: 32 MB drosselten die Inferenz massiv (ständige
        // Buffer-Neuallokation). 256 MB nur solange das Modell geladen
        // ist — entlade() räumt Cache + Modell wieder weg.
        MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)
    }

    func lade() async {
        if container != nil { status = .bereit; return }
        if case .laedt = status { return }
        status = .laedt(0)
        do {
            let geladen = try await LLMModelFactory.shared.loadContainer(
                configuration: ModelConfiguration(
                    id: Self.modellID, extraEOSTokens: ["<|im_end|>"])
            ) { fortschritt in
                Task { @MainActor in
                    if case .laedt = self.status {
                        self.status = .laedt(Int(fortschritt.fractionCompleted * 100))
                    }
                }
            }
            container = geladen
            status = .bereit
            armIdleTimer()
        } catch {
            status = .fehler(error.localizedDescription)
        }
    }

    func entlade() {
        idleTimer?.invalidate()
        idleTimer = nil
        container = nil
        MLX.GPU.clearCache()
        if status == .bereit { status = .nichtGeladen }
    }

    /// nil = Engine nicht nutzbar (Laden fehlgeschlagen) — Aufrufer fällt
    /// auf Apple FM zurück. Guardrails macht der Aufrufer (Cleanup.validate).
    func putze(_ text: String, anweisung: String) async -> String? {
        if container == nil { await lade() }
        guard let container else { return nil }
        armIdleTimer()

        // ChatML von Hand: die alte Jinja-Version im transformers-Stack
        // rendert Qwen3s Chat-Template nicht zuverlässig. /no_think
        // schaltet den Denk-Modus ab (sonst <think>-Block + Latenz).
        let prompt = """
        <|im_start|>system
        \(anweisung) /no_think<|im_end|>
        <|im_start|>user
        \(text)<|im_end|>
        <|im_start|>assistant
        """
        // Cleanup kürzt eher: Eingabelänge + Luft reicht als Deckel.
        let maxTokens = min(1024, text.count / 2 + 128)

        do {
            let roh: String = try await container.perform { context in
                let tokens = context.tokenizer.encode(text: prompt)
                let ergebnis = try MLXLMCommon.generate(
                    input: LMInput(tokens: MLXArray(tokens)),
                    parameters: GenerateParameters(temperature: 0.0),
                    context: context
                ) { bisher in
                    bisher.count >= maxTokens ? .stop : .more
                }
                return ergebnis.output
            }
            armIdleTimer()
            return Self.ohneDenkblock(roh)
        } catch {
            status = .fehler(error.localizedDescription)
            return nil
        }
    }

    /// Qwen3 stellt auch mit /no_think einen (leeren) <think>-Block voran.
    static func ohneDenkblock(_ text: String) -> String {
        var t = text
        if let start = t.range(of: "<think>"),
           let ende = t.range(of: "</think>"),
           start.lowerBound < ende.upperBound {
            t.removeSubrange(start.lowerBound ..< ende.upperBound)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func armIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(
            withTimeInterval: idleSekunden, repeats: false
        ) { _ in
            Task { @MainActor in QwenCleanup.shared.entlade() }
        }
    }
}
