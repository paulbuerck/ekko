// Sources/Ekko/PrompterFenster.swift
import SwiftUI
import AppKit

/// Teleprompter-Panel: dunkles Glas,
/// kameranah oben, always-on-top, nonactivating (Ziel-App behält Fokus).
/// Gelesen = gedimmt, aktuelle Position = Petrol-Highlight, Klick aufs
/// Wort setzt die Position, Deckkraft-Slider 5–95 %.
@MainActor
final class PrompterFenster: ObservableObject {
    @Published var aligner: Aligner
    @Published var pausiert = false
    @Published var deckkraft: Double = 0.88
    @Published var schrift: Double = 24
    @Published var wartet = false
    let titel: String
    let start = Date()
    var onStopp: (() -> Void)?

    private var panel: NSPanel?
    private var zuletztBewegt = Date()

    init(titel: String, skript: String) {
        self.titel = titel
        self.aligner = Aligner(skript: skript)
    }

    /// STT-Stand einarbeiten (bestätigt + Hypothese als ein Text).
    func hoere(_ text: String) {
        guard !pausiert else { return }
        let vorher = aligner.position
        aligner.hoere(text)
        if aligner.position != vorher { zuletztBewegt = Date() }
        // > 10 s kein Fortschritt (Pause oder vom Skript abgewichen) → „wartet"
        wartet = Date().timeIntervalSince(zuletztBewegt) > 10
    }

    func zeige() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(
            rootView: PrompterView(ctrl: self))
        if let schirm = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(CGPoint(
                x: schirm.midX - 320,
                y: schirm.maxY - 300 - 24))  // kameranah oben Mitte
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func schliesse() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct PrompterView: View {
    @ObservedObject var ctrl: PrompterFenster

    var body: some View {
        VStack(spacing: 0) {
            kopf
            Divider().overlay(Color.white.opacity(0.09))
            wortFluss
            Divider().overlay(Color.white.opacity(0.09))
            fuss
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .opacity(max(ctrl.deckkraft, 0.15))
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.094, green: 0.102, blue: 0.118))
                    .opacity(ctrl.deckkraft)
            })
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
        .frame(width: 640, height: 300)
        .preferredColorScheme(.dark)  // Panel bewusst immer dunkel
    }

    private var kopf: some View {
        HStack(spacing: 9) {
            ImpulsZeichen(farbe: Color(red: 0.286, green: 0.749, blue: 0.792),
                          groesse: 15)
            Text(ctrl.titel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
            Text(ctrl.wartet ? "· wartet auf dich"
                             : "· folgt deiner Stimme")
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.286, green: 0.749, blue: 0.792))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(EkkoFarbe.meeting).frame(width: 7, height: 7)
                Text(ctrl.start, style: .timer)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(EkkoFarbe.meeting)
            Button { ctrl.onStopp?() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var wortFluss: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                FlussLayout(abstand: ctrl.schrift * 0.32,
                            zeilenAbstand: ctrl.schrift * 0.45) {
                    ForEach(Array(ctrl.aligner.woerter.enumerated()),
                            id: \.offset) { i, wort in
                        Text(wort)
                            .font(.system(size: ctrl.schrift, weight: .medium))
                            .foregroundStyle(farbe(i))
                            .padding(.horizontal, i == ctrl.aligner.position ? 3 : 0)
                            .background(
                                i == ctrl.aligner.position
                                    ? Color(red: 0.286, green: 0.749,
                                            blue: 0.792).opacity(0.28)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5))
                            .id(i)
                            .onTapGesture { ctrl.aligner.setzePosition(i) }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
            }
            .onChange(of: ctrl.aligner.position) { _, neu in
                withAnimation(.easeOut(duration: 0.35)) {
                    proxy.scrollTo(min(neu, ctrl.aligner.woerter.count - 1),
                                   anchor: .center)
                }
            }
        }
    }

    private func farbe(_ i: Int) -> Color {
        if i < ctrl.aligner.position { return .white.opacity(0.32) }
        if i == ctrl.aligner.position { return .white }
        return .white.opacity(0.88)
    }

    private var fuss: some View {
        HStack(spacing: 10) {
            Button {
                ctrl.pausiert.toggle()
            } label: {
                Image(systemName: ctrl.pausiert ? "play.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.85))
            Button("A−") { ctrl.schrift = max(16, ctrl.schrift - 2) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
            Button("A+") { ctrl.schrift = min(40, ctrl.schrift + 2) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 6) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                Slider(value: $ctrl.deckkraft, in: 0.05...0.95)
                    .controlSize(.mini)
                    .frame(width: 74)
            }
            ProgressView(value: ctrl.aligner.fortschritt)
                .progressViewStyle(.linear)
                .tint(Color(red: 0.286, green: 0.749, blue: 0.792))
            Text("Klick auf Wort = Position setzen")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Einfaches Flow-Layout: Wörter fließen wie Text, jedes bleibt eine
/// eigene, klickbare View.
private struct FlussLayout: Layout {
    var abstand: CGFloat
    var zeilenAbstand: CGFloat

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews, cache: inout ()) -> CGSize {
        anordnen(breite: proposal.width ?? 600, subviews: subviews).groesse
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let plan = anordnen(breite: bounds.width, subviews: subviews)
        for (i, punkt) in plan.punkte.enumerated() {
            subviews[i].place(
                at: CGPoint(x: bounds.minX + punkt.x,
                            y: bounds.minY + punkt.y),
                proposal: .unspecified)
        }
    }

    private func anordnen(breite: CGFloat, subviews: Subviews)
        -> (punkte: [CGPoint], groesse: CGSize) {
        var punkte: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, zeilenHoehe: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x > 0, x + s.width > breite {
                x = 0
                y += zeilenHoehe + zeilenAbstand
                zeilenHoehe = 0
            }
            punkte.append(CGPoint(x: x, y: y))
            x += s.width + abstand
            zeilenHoehe = max(zeilenHoehe, s.height)
        }
        return (punkte, CGSize(width: breite, height: y + zeilenHoehe))
    }
}
