# Ekko

On-device dictation for macOS: hold the right ⌥ key, speak, let go — the text lands wherever your cursor is. Nothing leaves your Mac.

<!-- TODO: screenshot or GIF here (pill while dictating, ~1200 px wide), e.g.
     ![Ekko dictating into a text field](docs/images/demo.gif)
     Add the file under docs/images/ first, then uncomment the line above. -->

## Install

Requirements: macOS 26, Apple Silicon, Xcode toolchain, an Apple Development certificate (`security find-identity -p codesigning -v`). Optional: `brew install yt-dlp` for link import.

    git clone https://github.com/paulbuerck/ekko && cd ekko
    ./deploy.sh

`deploy.sh` signs with your only Apple Development identity; if you have several, set `EKKO_IDENTITAET="Apple Development: Your Name (TEAMID)"`. On first launch Ekko downloads the speech model (~630 MB).

### Permissions

Grant once: **Input Monitoring** (hotkey), **Accessibility** (pasting), **Microphone**, and **Screen Recording** for meetings.

If macOS asks for them again after a rebuild, the signing identity changed: always sign with the same identity (never ad-hoc `-s -`), or macOS drops these permissions.

## Use

| | |
|---|---|
| Hold right ⌥ | Dictate into the focused text field |
| Double-tap right ⌥ | Meeting recording (mic + system audio) → `~/Diktate/` |
| Drop a file on the pill | Transcribe audio/video |
| ⌘E · menu bar | Window: Home, Dictionary, Style, Transcripts, Teleprompter, Import · ⌘, Settings |

Ekko learns names and jargon from your corrections (`~/Diktate/woerterbuch.txt`). The UI follows your macOS language (German or English).

## Develop

Run the tests with `swift test`. How it works: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Security reports: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Third-party components: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
