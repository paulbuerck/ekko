import XCTest
import AppKit
@testable import Ekko

final class HotkeyModifierTests: XCTestCase {
    func testKeycodesEindeutig() {
        let codes = HotkeyModifier.allCases.map(\.keycode)
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    func testRechteOptionBleibtKeycode61() {
        // Rückwärtskompatibel zum bisherigen fixen Hotkey.
        XCTAssertEqual(HotkeyModifier.rechteOption.keycode, 61)
        XCTAssertEqual(HotkeyModifier.rechteOption.flag, .maskAlternate)
    }

    func testFlagsPassenZurTaste() {
        XCTAssertEqual(HotkeyModifier.rechteControl.flag, .maskControl)
        XCTAssertEqual(HotkeyModifier.rechteCommand.flag, .maskCommand)
        XCTAssertEqual(HotkeyModifier.fn.flag, .maskSecondaryFn)
    }

    func testPersistenzRoundTrip() {
        let vorher = HotkeyModifier.gespeichert
        defer { HotkeyModifier.gespeichert = vorher }
        HotkeyModifier.gespeichert = .fn
        XCTAssertEqual(HotkeyModifier.gespeichert, .fn)
        HotkeyModifier.gespeichert = .rechteCommand
        XCTAssertEqual(HotkeyModifier.gespeichert, .rechteCommand)
    }

    func testDefaultIstRechteOption() {
        let key = "hotkeyModifier"
        let vorher = UserDefaults.standard.string(forKey: key)
        defer {
            if let vorher { UserDefaults.standard.set(vorher, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(HotkeyModifier.gespeichert, .rechteOption)
    }
}
