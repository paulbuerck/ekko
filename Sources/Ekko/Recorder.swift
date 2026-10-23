@preconcurrency import AVFoundation

/// Mikrofon-Aufnahme über AVAudioEngine. Liefert beim Stopp die Samples
/// als 16-kHz-Mono-Float-Puffer (Format, das SpeechAnalyzer nimmt).
/// @unchecked Sendable: alle geteilten Zustände sind lock-geschützt —
/// der Streaming-Loop (Live-Text) liest Snapshots von einem Hintergrund-Task.
final class Recorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var buffers: [AVAudioPCMBuffer] = []
    private let lock = NSLock()  // Audio-Render-Thread vs. Main
    private let format: AVAudioFormat
    /// Pegel 0…1 (RMS, geglättet) — fürs Sonar-HUD. Wird vom
    /// Audio-Thread geschrieben, vom UI-Timer gelesen.
    private let levelLock = NSLock()
    private var _level: Float = 0
    var level: Float {
        levelLock.lock()
        defer { levelLock.unlock() }
        return _level
    }

    init() {
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
            channels: 1, interleaved: false)!
    }

    func start() throws {
        lock.lock()
        buffers.removeAll()
        lock.unlock()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: format)
        else {
            throw NSError(
                domain: "de.paul.ekko.recorder", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Kein Audio-Konverter für Eingabeformat \(inputFormat)"])
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self else { return }
            let ratio = self.format.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(
                Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(
                pcmFormat: self.format, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, out.frameLength > 0 {
                self.lock.lock()
                self.buffers.append(out)
                self.lock.unlock()
                let n = Int(out.frameLength)
                let data = out.floatChannelData![0]
                var sum: Float = 0
                for i in 0..<n { sum += data[i] * data[i] }
                let rms = min(1, sqrt(sum / Float(n)) * 6)  // ~Sprechpegel
                self.levelLock.lock()
                self._level = 0.6 * self._level + 0.4 * rms
                self.levelLock.unlock()
            }
        }
        engine.prepare()
        try engine.start()
    }

    /// Kopie aller bisher gesammelten Samples — für den Live-Streaming-
    /// Pass während der Aufnahme. Thread-sicher, Aufnahme läuft weiter.
    func samplesSnapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let total = buffers.reduce(0) { $0 + Int($1.frameLength) }
        var out = [Float]()
        out.reserveCapacity(total)
        for b in buffers {
            out.append(contentsOf: UnsafeBufferPointer(
                start: b.floatChannelData![0], count: Int(b.frameLength)))
        }
        return out
    }

    /// Stoppt und liefert die gesammelten Samples als einen Puffer.
    func stop() -> AVAudioPCMBuffer? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        let collected = buffers
        buffers.removeAll()
        lock.unlock()
        let total = collected.reduce(0) { $0 + $1.frameLength }
        guard total > 0,
              let joined = AVAudioPCMBuffer(
                  pcmFormat: format, frameCapacity: total) else { return nil }
        for b in collected {
            joined.append(b)
        }
        return joined
    }
}

private extension AVAudioPCMBuffer {
    func append(_ other: AVAudioPCMBuffer) {
        let dst = floatChannelData![0] + Int(frameLength)
        let src = other.floatChannelData![0]
        dst.update(from: src, count: Int(other.frameLength))
        frameLength += other.frameLength
    }
}
