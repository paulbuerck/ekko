// Sources/Ekko/EkkoDesign.swift
//
// Eine Quelle der Wahrheit für die visuelle Ekko-Identität.
// Farbsprache aus dem eigenen Sonar-HUD: Petrol/Teal = App-Akzent
// (Diktat/Sonar), Orange = Meeting (wie die orangen HUD-Ringe).
//
// SwiftPM hat keinen Asset-Katalog → dynamische (Light/Dark-fähige)
// Farben über NSColor(name:dynamicProvider:), aufgelöst per
// appearance.bestMatch(from:).
import SwiftUI
import AppKit

enum EkkoFarbe {
    /// Petrol/Sonar — der App-Akzent (Diktat).
    static let akzent = dynamisch(hell: 0x12747F, dunkel: 0x49BFCA)
    /// Getönter Akzent-Hintergrund (Icon-Kacheln, Auswahl-Tönung).
    static let akzentWeich = dynamisch(hell: 0xE4F1F2, dunkel: 0x123033)
    /// Orange — Meeting (wie die Meeting-Ringe im HUD).
    static let meeting = dynamisch(hell: 0xD9822B, dunkel: 0xE6A25B)
    /// Getönter Meeting-Hintergrund.
    static let meetingWeich = dynamisch(hell: 0xFBEEDE, dunkel: 0x33291B)

    private static func dynamisch(hell: Int, dunkel: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let istDunkel = appearance.bestMatch(
                from: [.aqua, .darkAqua]) == .darkAqua
            return nsColor(istDunkel ? dunkel : hell)
        })
    }

    private static func nsColor(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: 1)
    }
}

enum EkkoMetrik {
    /// Eckenradius für Icon-Kacheln und Toolbar-Knöpfe.
    static let kachelRadius: CGFloat = 7
}

/// Signatur-Zeichen „Impuls": die drei Balken aus dem App-Icon
/// (Proportionen wie im App-Icon).
/// Mitte voll, Seiten leicht transparent. Ersetzt den Sonar-Ring
/// (Fenster-Zeichen und App-Icon zeigen dasselbe Motiv).
struct ImpulsZeichen: View {
    var farbe: Color = EkkoFarbe.akzent
    var groesse: CGFloat = 16

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let breite = s * 0.2
            // (Mitte x, Höhe, Deckkraft) relativ zur Kantenlänge
            for (x, h, deckung) in [(0.22, 0.42, 0.75), (0.5, 0.9, 1.0),
                                    (0.78, 0.58, 0.75)] as [(Double, Double, Double)] {
                let hoehe = s * h
                let rect = CGRect(x: size.width / 2 - s / 2 + s * x - breite / 2,
                                  y: size.height / 2 - hoehe / 2,
                                  width: breite, height: hoehe)
                ctx.fill(Path(roundedRect: rect, cornerRadius: breite / 2),
                         with: .color(farbe.opacity(deckung)))
            }
        }
        .frame(width: groesse, height: groesse)
    }
}

/// Tastenkappe: echte Taste statt Symbol im Fließtext („rechte [⌥]").
struct TasteKappe: View {
    let text: String
    var groesse: CGFloat = 11

    var body: some View {
        Text(text)
            .font(.system(size: groesse, weight: .medium, design: .rounded))
            .padding(.horizontal, groesse * 0.5)
            .frame(minWidth: groesse * 1.9, minHeight: groesse * 1.75)
            .background(.background, in: RoundedRectangle(cornerRadius: groesse * 0.4))
            .overlay(RoundedRectangle(cornerRadius: groesse * 0.4)
                .strokeBorder(.separator, lineWidth: 0.75))
            .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
    }
}

/// „rechte [⌥] halten …" — Hotkey als Kappe mit umgebendem Text.
struct HotkeyHinweis: View {
    let hotkey: HotkeyModifier
    let rest: LocalizedStringKey
    var groesse: CGFloat = 13

    var body: some View {
        HStack(spacing: 5) {
            if let seite = hotkey.seite { Text(seite) }
            TasteKappe(text: hotkey.symbol, groesse: groesse - 2)
            Text(rest)
        }
        .font(.system(size: groesse))
    }
}

/// Das echte App-Icon (pixelgenau das Logo) — für den Markenkopf.
struct AppIconBild: View {
    var groesse: CGFloat = 26
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: groesse, height: groesse)
    }
}

// MARK: - Fehler-Oberfläche
//
// Eine kleine, wiederverwendbare Fehlerdarstellung (statt stiller
// try?-Schlucker): sichtbare, knappe Meldung in der
// Stimme des Interfaces — was schiefging und, wo möglich, was zu tun ist.

struct EkkoFehler: Identifiable {
    let id = UUID()
    let text: String
}

extension View {
    /// Zeigt einen gebundenen EkkoFehler als Ekko-getönten Alert.
    func ekkoFehler(_ fehler: Binding<EkkoFehler?>) -> some View {
        alert(
            "Ekko",
            isPresented: Binding(
                get: { fehler.wrappedValue != nil },
                set: { if !$0 { fehler.wrappedValue = nil } }),
            presenting: fehler.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { f in
            Text(f.text)
        }
    }
}

// MARK: - Seitenbausteine (Interface 2026-10-23, nach HIG)

/// Markenschrift Sora (OFL, Resources/Fonts) für Logo, Seitentitel und
/// Kennzahlen — runde Formen wie die Sonar-Kreise.
/// Fließtext und Bedienelemente bleiben Systemschrift (HIG).
enum EkkoSchrift {
    /// Einmal beim Start: Font aus dem App-Paket nur für Ekko registrieren.
    static func registriere() {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("Fonts/Sora-Variable.ttf"),
              FileManager.default.fileExists(atPath: url.path)
        else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// Sora in beliebiger Strichstärke (variable Achse `wght` 100–800);
    /// ohne registrierten Font fällt NSFont auf die Systemschrift zurück.
    static func sora(_ groesse: CGFloat, gewicht: CGFloat = 500) -> Font {
        let wght = NSNumber(value: 0x7767_6874)  // 'wght'
        let deskriptor = NSFontDescriptor(fontAttributes: [
            .family: "Sora",
            NSFontDescriptor.AttributeName(
                rawValue: kCTFontVariationAttribute as String): [wght: gewicht],
        ])
        let nsFont = NSFont(descriptor: deskriptor, size: groesse)
        guard let nsFont, nsFont.familyName == "Sora" else {
            return .system(size: groesse, weight: gewicht >= 600 ? .semibold : .medium)
        }
        return Font(nsFont)
    }

    /// Große Kennzahlen.
    static func zahl(_ groesse: CGFloat = 30) -> Font { sora(groesse, gewicht: 400) }
    /// Seitentitel.
    static func titel(_ groesse: CGFloat = 26) -> Font { sora(groesse, gewicht: 600) }
}

/// Einheitlicher Seitenkopf: großer Titel + optionaler Untertitel.
struct SeitenKopf: View {
    let titel: String
    var untertitel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titel)
                .font(EkkoSchrift.titel())
                .tracking(-0.4)
            if let untertitel {
                Text(untertitel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Karte: leicht abgesetzte Fläche mit feinem Rand (Light/Dark).
    func ekkoKarte(innen: CGFloat = 16) -> some View {
        padding(innen)
            .background(.background.secondary,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
    }

    /// Standard-Seitenrahmen: scrollbar, Inhalt mittig begrenzt.
    func ekkoSeite() -> some View {
        ScrollView {
            self
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, 36)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
    }
}
