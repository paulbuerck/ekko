import Foundation

/// Zustandsautomat der Hotkey-Geste (im Alltag erprobt):
/// Halten (>= tapWindow) = Diktat. Kurztipp + zweiter Down binnen
/// tapWindow nach dem Up = Doppeltipp (Meeting an/aus).
enum TapAction: Equatable {
    case start, stop, cancel, doubleTap
}

struct TapDetector {
    static let tapWindow: TimeInterval = 0.4

    private var downAt: TimeInterval?
    private var armedUntil: TimeInterval?  // Kurztipp-Up + Fenster
    private var suppressUp = false         // Up nach doubleTap schluckt nichts

    mutating func onFlags(down: Bool, at t: TimeInterval) -> TapAction? {
        if down {
            if let armed = armedUntil, t <= armed {
                armedUntil = nil
                downAt = nil
                suppressUp = true
                return .doubleTap
            }
            armedUntil = nil
            downAt = t
            return .start
        }
        // Up:
        if suppressUp {
            suppressUp = false
            return nil
        }
        guard let began = downAt else { return nil }
        downAt = nil
        if t - began < Self.tapWindow {
            armedUntil = t + Self.tapWindow
            return .cancel
        }
        return .stop
    }
}
