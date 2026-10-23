import AVFoundation

enum MediaExtractorFehler: LocalizedError {
    case keineAudiospur
    case exportFehlgeschlagen(String)

    var errorDescription: String? {
        switch self {
        case .keineAudiospur:
            return String(localized: "Datei enthält keine Audiospur.")
        case .exportFehlgeschlagen(let grund):
            return String(localized: "Audio-Export fehlgeschlagen: \(grund)")
        }
    }
}

/// Macht aus beliebigen Mediendateien etwas, das AVAudioFile lesen kann.
/// Audio-Dateien (wav/m4a/mp3/aiff/caf): unverändert zurück.
/// Video-Container (mov/mp4/m4v): Audiospur als temporäres .m4a.
enum MediaExtractor {
    private static let audioEndungen: Set<String> =
        ["wav", "m4a", "mp3", "aiff", "aif", "caf", "flac"]

    static func audioURL(for url: URL) async throws -> URL {
        if audioEndungen.contains(url.pathExtension.lowercased()) {
            return url
        }
        let asset = AVURLAsset(url: url)
        let spuren = try await asset.loadTracks(withMediaType: .audio)
        guard !spuren.isEmpty else {
            throw MediaExtractorFehler.keineAudiospur
        }
        guard let session = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MediaExtractorFehler.exportFehlgeschlagen(
                "kein Export-Preset (AppleM4A)")
        }
        let ziel = FileManager.default.temporaryDirectory
            .appendingPathComponent("ekko-\(UUID().uuidString).m4a")
        do {
            try await session.export(to: ziel, as: .m4a)
        } catch {
            throw MediaExtractorFehler.exportFehlgeschlagen(
                error.localizedDescription)
        }
        return ziel
    }
}
