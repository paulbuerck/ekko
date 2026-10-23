import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics

enum Ampel { case gruen, gelb, rot }

enum Berechtigung: String, CaseIterable, Identifiable {
    case eingabemonitoring = "Eingabemonitoring"
    case bedienungshilfen = "Bedienungshilfen"
    case mikrofon = "Mikrofon"
    case bildschirm = "Bildschirmaufnahme"
    var id: String { rawValue }

    /// Angezeigter Name (lokalisiert; `rawValue` bleibt die ID).
    var name: String {
        switch self {
        case .eingabemonitoring: return String(localized: "Eingabemonitoring")
        case .bedienungshilfen: return String(localized: "Bedienungshilfen")
        case .mikrofon: return String(localized: "Mikrofon")
        case .bildschirm: return String(localized: "Bildschirmaufnahme")
        }
    }

    var zweck: String {
        switch self {
        case .eingabemonitoring: return String(localized: "⌥-Hotkey (Diktat auslösen)")
        case .bedienungshilfen: return String(localized: "⌘V-Einfügen")
        case .mikrofon: return String(localized: "Aufnahme")
        case .bildschirm: return String(localized: "Meeting-System-Audio")
        }
    }

    var status: Ampel {
        switch self {
        case .eingabemonitoring:
            return CGPreflightListenEventAccess() ? .gruen : .rot
        case .bedienungshilfen:
            return AXIsProcessTrusted() ? .gruen : .rot
        case .mikrofon:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .gruen
            case .notDetermined: return .gelb
            default: return .rot
            }
        case .bildschirm:
            return CGPreflightScreenCaptureAccess() ? .gruen : .rot
        }
    }

    private var einstellungsAnker: String {
        switch self {
        case .eingabemonitoring: return "Privacy_ListenEvent"
        case .bedienungshilfen: return "Privacy_Accessibility"
        case .mikrofon: return "Privacy_Microphone"
        case .bildschirm: return "Privacy_ScreenCapture"
        }
    }

    func oeffneEinstellung() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?\(einstellungsAnker)")!
        NSWorkspace.shared.open(url)
    }
}
