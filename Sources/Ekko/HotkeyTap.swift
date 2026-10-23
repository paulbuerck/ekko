import AppKit
import os

/// CGEventTap auf flagsChanged, gehaltene Modifier-Taste (Default rechte ⌥).
/// `modifier` ist live umschaltbar — der Tap filtert pro Event darauf, kein
/// Neustart nötig. Erfahrungswerte: DisabledBy-Events reaktivieren
/// den Tap, Callback macht NIE Arbeit (delegiert sofort).
final class HotkeyTap {
    /// Welche Taste ausgewertet wird. Von EkkoApp aus AppState gesetzt.
    var modifier: HotkeyModifier = .rechteOption
    private var tap: CFMachPort?
    private var detector = TapDetector()
    var onAction: (@MainActor (TapAction) -> Void)?

    private let log = Logger(subsystem: "de.paul.ekko", category: "tap")

    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<HotkeyTap>
                .fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(
        type: CGEventType, event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                log.warning("Tap war deaktiviert (\(type.rawValue)) — reaktiviert")
            }
            return Unmanaged.passUnretained(event)
        }
        let m = modifier
        guard type == .flagsChanged,
              event.getIntegerValueField(.keyboardEventKeycode) == m.keycode
        else { return Unmanaged.passUnretained(event) }
        log.info("flagsChanged: Keycode \(m.keycode), flags=\(event.flags.rawValue)")
        let down = event.flags.contains(m.flag)
        if let action = detector.onFlags(
            down: down, at: ProcessInfo.processInfo.systemUptime) {
            // Callback läuft auf dem Main-Runloop (Source dort registriert):
            let handler = onAction
            MainActor.assumeIsolated {
                handler?(action)
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
