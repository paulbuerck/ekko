// Sources/Ekko/Downloader.swift
import Foundation
import os

enum Downloader {
    enum Fehler: LocalizedError {
        case fehlt, prozess(String)
        var errorDescription: String? {
            switch self {
            case .fehlt: return String(localized: "yt-dlp nicht gefunden (brew install yt-dlp)")
            case .prozess(let s): return "yt-dlp: \(s)"
            }
        }
    }

    static var pfad: URL? {
        let kandidaten = ["/opt/homebrew/bin/yt-dlp",
                          "/usr/local/bin/yt-dlp"]
        for p in kandidaten where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }
    static var vorhanden: Bool { pfad != nil }

    /// Ziel ohne Endung übergeben — yt-dlp hängt die Container-Endung an.
    /// `--cookies-from-browser safari`: YouTube verlangt Login-Cookies
    /// (Bot-Schutz); Ekko braucht dafür Vollzugriff (Full Disk Access),
    /// um Safaris Cookie-Container zu lesen.
    static func argumente(fuer url: URL, ziel: URL) -> [String] {
        ["-x", "--audio-format", "m4a",
         "--cookies-from-browser", "safari",
         "--write-info-json",
         "-o", ziel.deletingPathExtension().path + ".%(ext)s",
         url.absoluteString]
    }

    /// Pfad der von `--write-info-json` erzeugten Metadaten-Datei zu `ziel`.
    static func infoJSONPfad(fuer ziel: URL) -> URL {
        ziel.deletingPathExtension()
            .appendingPathExtension("info.json")
    }

    static func lade(_ url: URL) async throws -> (audio: URL, titel: String?) {
        guard let bin = pfad else { throw Fehler.fehlt }
        let ziel = FileManager.default.temporaryDirectory
            .appendingPathComponent("ekko-\(UUID().uuidString).m4a")
        let proc = Process()
        proc.executableURL = bin
        proc.arguments = argumente(fuer: url, ziel: ziel)
        // Per Finder gestartete .regular-App erbt nur ein minimales PATH
        // (/usr/bin:/bin) — ohne /opt/homebrew/bin findet yt-dlp die
        // JavaScript-Runtime (deno) nicht und YouTube-Extraktion scheitert.
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin",
                     "\(NSHomeDirectory())/.bun/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin"])
            .joined(separator: ":")
        proc.environment = env
        let err = Pipe()
        proc.standardError = err
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proc.terminationHandler = { _ in
                continuation.resume()
            }
            do {
                try proc.run()
            } catch {
                proc.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        let log = Logger(subsystem: "de.paul.ekko", category: "downloader")
        guard proc.terminationStatus == 0 else {
            let d = err.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: d, encoding: .utf8) ?? "Fehler"
            log.error("yt-dlp exit \(proc.terminationStatus): \(text, privacy: .public)")
            throw Fehler.prozess(text)
        }
        guard FileManager.default.fileExists(atPath: ziel.path) else {
            let d = err.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: d, encoding: .utf8) ?? ""
            log.error("yt-dlp exit 0 aber keine Datei. stderr: \(text, privacy: .public)")
            throw Fehler.prozess(String(localized: "keine Audio-Datei erzeugt"))
        }
        return (ziel, titelAusInfoJSON(fuer: ziel))
    }

    /// Liest `title` aus der `--write-info-json`-Datei und räumt sie weg.
    /// nil, wenn die Datei fehlt oder keinen Titel hat — dann greift der
    /// Fallback auf den URL-Namen in der Ablage.
    private static func titelAusInfoJSON(fuer ziel: URL) -> String? {
        let pfad = infoJSONPfad(fuer: ziel)
        defer { try? FileManager.default.removeItem(at: pfad) }
        guard let daten = try? Data(contentsOf: pfad),
              let obj = try? JSONSerialization.jsonObject(with: daten)
                as? [String: Any],
              let titel = obj["title"] as? String,
              !titel.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return titel
    }
}
