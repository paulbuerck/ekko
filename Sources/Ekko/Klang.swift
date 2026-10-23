import AppKit

/// Leise Start-/Stopp-Töne fürs Diktat. Zur Laufzeit
/// erzeugt — zwei kurze Sinus-Töne mit weicher Hüllkurve, keine
/// Sounddateien. Abschaltbar in den Einstellungen (`toeneAn`).
@MainActor
enum Klang {
    private static let start = ton([880, 1318.5])   // A5 → E6, aufsteigend
    private static let stopp = ton([1318.5, 880])   // absteigend

    static func spieleStart() { spiele(start) }
    static func spieleStopp() { spiele(stopp) }

    private static func spiele(_ klang: NSSound?) {
        guard UserDefaults.standard.object(forKey: "toeneAn") as? Bool ?? true,
              let klang else { return }
        klang.stop()
        klang.play()
    }

    /// Folge kurzer Töne als WAV (16 bit, 44,1 kHz, mono) im Speicher.
    private static func ton(_ frequenzen: [Double]) -> NSSound? {
        let rate = 44_100.0, dauer = 0.07, lautstaerke = 0.18
        var samples: [Int16] = []
        for f in frequenzen {
            let n = Int(rate * dauer)
            for i in 0..<n {
                let t = Double(i) / rate
                let huelle = min(1, t / 0.004) * exp(-t * 38)  // weich an, ausklingend
                let wert = (sin(2 * .pi * f * t) + 0.3 * sin(4 * .pi * f * t))
                    * huelle * lautstaerke / 1.3
                samples.append(Int16(max(-1, min(1, wert)) * Double(Int16.max)))
            }
        }
        var daten = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { daten.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { daten.append(contentsOf: $0) } }
        let nutz = UInt32(samples.count * 2)
        daten.append(contentsOf: Array("RIFF".utf8)); u32(36 + nutz)
        daten.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        daten.append(contentsOf: Array("data".utf8)); u32(nutz)
        samples.forEach { u16(UInt16(bitPattern: $0)) }
        return NSSound(data: daten)
    }
}
