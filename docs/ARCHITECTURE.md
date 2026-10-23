# Ekko — Architecture

Dictation and transcription for macOS, fully on-device: speech recognition, clean-up and learning run locally; no audio or text is sent anywhere.

## Features

**Dictation.** Hold a modifier key (default: right ⌥), speak, release. A live caption shows the text near the cursor while you speak; on release the final text is pasted into the focused app.

- **Pasting** puts the text on the pasteboard as a lazily provided item and sends ⌘V. The previous pasteboard (all items and types) is restored 500 ms after the target app has read the text; if no app reads it within 2 s, the dictation stays on the pasteboard and a hint appears. Ekko remembers the focused element at the start, refocuses it before pasting, and never pastes into password fields.
- **Style profiles** map apps to a tone (formal, short, structured, raw) for the optional clean-up.
- **Clean-up (optional)** removes filler words and self-corrections with an on-device LLM — Apple Foundation Models inline, or Qwen3-4B via MLX. Guardrails (length ratio, word overlap, question protection) keep the raw transcript whenever the model drifts.
- **Learning dictionary.** After a paste Ekko re-reads the field once (next dictation or after 30 s). If you replaced one or two words with similar ones (e.g. "schieba" → "Shiba"), it adds a rule to `~/Diktate/woerterbuch.txt` and shows a "learned" pill. Rewrites, additions and content changes are ignored.
- **Statistics.** Words, dictations per day, streak and average latency (release → text) are stored as numbers only in `~/Library/Application Support/Ekko/statistik.json`. Dictation text is never persisted; the history lives in memory.

**Meetings.** Double-tap the hotkey. Ekko records the microphone and the system audio (the other side of a call) as separate tracks and writes a transcript with "you/others" to `~/Diktate/`.

**Import.** Drop audio/video on the pill or the Import page, or paste a link (via `yt-dlp`). A local queue transcribes in the background; dictation always has priority.

**Teleprompter.** Scripts in `~/Diktate/Teleprompter/`. While you read aloud, a word aligner matches the growing transcript against the script and scrolls along.

**Interface.** A pill at the bottom of the screen shows state: dot = ready, live waveform = recording, travelling wave = transcribing, orange = meeting. The main window has a sidebar (Home, Dictionary, Style, Transcripts, Teleprompter, Import); settings open in their own window (⌘,). Light/dark/system appearance, German/English UI.

## Build

Swift 6, macOS 26+, Swift Package Manager, one executable target. `deploy.sh` builds in release mode, assembles `Ekko.app` (binary, MLX metallib, Sora font, localizations), signs it with a stable identity and launches it.

Dependencies (pinned on purpose in `Package.swift`):

- **WhisperKit** — speech recognition on the Neural Engine (`large-v3-turbo`, automatic language detection, prewarmed at launch).
- **mlx-swift-examples 2.21.2 / mlx-swift 0.21.3** — MLX runtime for the Qwen clean-up; the last versions compatible with WhisperKit's swift-transformers pin. Qwen3 is not part of mlx-swift-examples, so Ekko ships its own port (`Qwen3Modell.swift`).

Typical latency from releasing the key to finished text is 0.7–1.3 s on an M2 (5–38 s of speech).

## Source map

| Area | Files |
|---|---|
| App & state | `EkkoApp.swift`, `AppState.swift`, `Statistik.swift` |
| Hotkey | `HotkeyTap.swift`, `TapDetector.swift`, `HotkeyModifier.swift` |
| Audio | `Recorder.swift`, `MeetingRecorder.swift`, `SystemAudioRecorder.swift` |
| Speech recognition | `WhisperTranscriber.swift`, `LiveKonfirmation.swift`, `Transcriber.swift` |
| Clean-up & style | `Cleanup.swift`, `QwenCleanup.swift`, `Qwen3Modell.swift`, `StilProfil.swift` |
| Pasting & target field | `Paster.swift`, `Zielfeld.swift`, `CursorPosition.swift` |
| Dictionary & learning | `Woerterbuch.swift`, `WoerterbuchEditor.swift`, `KorrekturLerner.swift` |
| Import | `TranskriptionsQueue.swift`, `MediaExtractor.swift`, `Downloader.swift` |
| Teleprompter | `PrompterFenster.swift`, `Aligner.swift`, `ScriptStore.swift` |
| UI | `SonarHUD.swift` (pill), `CaptionFenster.swift`, `HauptFenster.swift`, `EkkoDesign.swift`, `Klang.swift`, `Panes/` |
| System | `Berechtigungen.swift`, `Speicher.swift` |

Identifiers and comments are in German.

## Headless probes

Besides unit tests, the binary has CLI flags that drive the real signal path with file audio, without UI:

- `Ekko --stream-probe <wav> [seconds]` — live streaming path in simulated real time; prints release → final-text latency.
- `Ekko --bench-whisper <wav> <model> [runs] [de|en|auto]` — speech-recognition latency and RAM.
- `Ekko --bench-prompt <model> "<word, word>" <wav>…` — compares decoding with and without a vocabulary prompt (WhisperKit 0.14.1 returns empty text for prompts with the turbo model, so Ekko relies on the learned dictionary instead).
- `Ekko --file <audio|video>` — transcribe a file.
