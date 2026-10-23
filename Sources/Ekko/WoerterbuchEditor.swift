import Foundation

@MainActor
final class WoerterbuchEditor: ObservableObject {
    /// Eine Instanz für Einstellungen UND Lernen — sonst überschreibt
    /// eine Bearbeitung im offenen Fenster frisch gelernte Regeln.
    static let shared = WoerterbuchEditor()
    private let pfad: URL
    @Published private(set) var regeln: [(falsch: String, richtig: String)] = []

    init(pfad: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Diktate/woerterbuch.txt")) {
        self.pfad = pfad
        lade()
    }

    func lade() {
        guard let inhalt = try? String(contentsOf: pfad, encoding: .utf8)
        else { regeln = []; return }
        regeln = inhalt.split(separator: "\n").compactMap { zeile in
            let z = zeile.trimmingCharacters(in: .whitespaces)
            guard !z.isEmpty, !z.hasPrefix("#"), z.contains("->") else { return nil }
            let t = z.split(separator: "->", maxSplits: 1)
            guard t.count == 2 else { return nil }
            let f = t[0].trimmingCharacters(in: .whitespaces)
            let r = t[1].trimmingCharacters(in: .whitespaces)
            guard !f.isEmpty, !r.isEmpty else { return nil }
            return (f, r)
        }
    }

    func hinzufuegen(falsch: String, richtig: String) throws {
        let f = falsch.trimmingCharacters(in: .whitespaces)
        let r = richtig.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty, !r.isEmpty else { return }
        regeln.append((f, r))
        try schreibe()
    }

    func bearbeiten(index: Int, falsch: String, richtig: String) throws {
        guard regeln.indices.contains(index) else { return }
        let f = falsch.trimmingCharacters(in: .whitespaces)
        let r = richtig.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty, !r.isEmpty else { return }
        regeln[index] = (f, r)
        try schreibe()
    }

    func loesche(index: Int) throws {
        guard regeln.indices.contains(index) else { return }
        regeln.remove(at: index)
        try schreibe()
    }

    private func schreibe() throws {
        try FileManager.default.createDirectory(
            at: pfad.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let text = regeln.map { "\($0.falsch) -> \($0.richtig)" }
            .joined(separator: "\n") + "\n"
        try text.write(to: pfad, atomically: true, encoding: .utf8)
    }
}
