import ScreenCaptureKit
import AVFoundation
import os

/// System-Audio (Gegenseite in Calls) als eigene WAV-Spur.
/// ScreenCaptureKit-Audio-Stream, eigenes Prozess-Audio ausgeschlossen.
final class SystemAudioRecorder: NSObject, SCStreamOutput, @unchecked Sendable {
    private var stream: SCStream?
    private var datei: AVAudioFile?
    private var url: URL?
    private var puffer = 0
    private let lock = NSLock()
    private let log = Logger(subsystem: "de.paul.ekko", category: "sysaudio")

    func start(neben mikroURL: URL) async throws {
        let ziel = mikroURL.deletingPathExtension()
            .appendingPathExtension("system.wav")
        // Zustand SOFORT frisch: ein stehen gebliebenes `url` aus einem
        // gescheiterten/alten Lauf ließ Callbacks sonst in die ALTE Datei
        // schreiben (Befund 2026-07-09: 1500er-WAV wuchs um 17:21 wieder).
        lock.withLock {
            datei = nil
            puffer = 0
            url = nil
        }
        log.info("Start, TCC-Preflight Bildschirmaufnahme: \(CGPreflightScreenCaptureAccess())")
        let inhalt = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let display = inhalt.displays.first else {
            log.error("kein Display gefunden — kein System-Audio")
            return
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let konfig = SCStreamConfiguration()
        konfig.capturesAudio = true
        konfig.excludesCurrentProcessAudio = true
        konfig.width = 2   // Video-Pflichtfelder, wird verworfen
        konfig.height = 2
        konfig.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let s = SCStream(filter: filter, configuration: konfig, delegate: nil)
        try s.addStreamOutput(self, type: .audio,
                              sampleHandlerQueue: .global(qos: .userInitiated))
        // Ziel vor startCapture setzen: Callbacks können sofort danach
        // eintreffen und sollen in die NEUE Datei schreiben.
        lock.withLock { url = ziel }
        do {
            try await s.startCapture()
        } catch {
            lock.withLock { url = nil }
            throw error
        }
        stream = s
        log.info("Capture läuft: \(ziel.lastPathComponent)")
    }

    nonisolated func stream(_ stream: SCStream,
                            didOutputSampleBuffer sb: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .audio, let pcm = sb.asPCMBuffer else { return }
        lock.lock()
        defer { lock.unlock() }
        if datei == nil, let url {
            datei = try? AVAudioFile(
                forWriting: url, settings: pcm.format.settings)
        }
        try? datei?.write(from: pcm)
        puffer += 1
    }

    func stop() async -> URL? {
        try? await stream?.stopCapture()
        stream = nil
        return lock.withLock {
            let u = datei == nil ? nil : url
            log.info("Stop: \(self.puffer) Audio-Puffer, Datei: \(u?.lastPathComponent ?? "KEINE")")
            datei = nil
            puffer = 0
            url = nil  // sonst schreibt der nächste Lauf ins alte Ziel
            return u
        }
    }
}

extension CMSampleBuffer {
    /// CMSampleBuffer (Audio) -> AVAudioPCMBuffer
    var asPCMBuffer: AVAudioPCMBuffer? {
        guard let desc = formatDescription,
              let asbd = desc.audioStreamBasicDescription else { return nil }
        var mutableAsbd = asbd
        guard let format = AVAudioFormat(streamDescription: &mutableAsbd),
              let buf = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(numSamples))
        else { return nil }
        buf.frameLength = AVAudioFrameCount(numSamples)
        CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self, at: 0, frameCount: Int32(numSamples),
            into: buf.mutableAudioBufferList)
        return buf
    }
}
