import XCTest
@testable import Ekko

final class DownloaderTests: XCTestCase {
    func testArgumenteEnthaltenAudioExtraktionUndZiel() {
        let url = URL(string: "https://youtu.be/abc123")!
        let ziel = URL(fileURLWithPath: "/tmp/ekko-xyz.m4a")
        let args = Downloader.argumente(fuer: url, ziel: ziel)
        XCTAssertTrue(args.contains("-x"))
        XCTAssertTrue(args.contains("https://youtu.be/abc123"))
        XCTAssertTrue(args.contains(where: { $0.contains("/tmp/ekko-xyz") }))
        // YouTube-Cookies aus Safari (Bot-Schutz)
        XCTAssertTrue(args.contains("--cookies-from-browser"))
        XCTAssertTrue(args.contains("safari"))
    }

    func testArgumenteSchreibenInfoJSONFuerTitel() {
        let url = URL(string: "https://youtu.be/abc123")!
        let ziel = URL(fileURLWithPath: "/tmp/ekko-xyz.m4a")
        let args = Downloader.argumente(fuer: url, ziel: ziel)
        XCTAssertTrue(args.contains("--write-info-json"))
    }

    func testInfoJSONPfadNebenZiel() {
        let ziel = URL(fileURLWithPath: "/tmp/ekko-xyz.m4a")
        XCTAssertEqual(Downloader.infoJSONPfad(fuer: ziel).path,
                       "/tmp/ekko-xyz.info.json")
    }

    func testPfadIstNilOderExistierendeDatei() {
        XCTAssertEqual(Downloader.vorhanden, Downloader.pfad != nil)
        if let p = Downloader.pfad {
            XCTAssertTrue(FileManager.default.fileExists(atPath: p.path))
        }
    }
}
