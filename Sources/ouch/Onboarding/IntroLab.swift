// Onboarding: `ouch introlab`, a window to audition the intro music arrangements.
import AppKit
import SwiftUI

/// `ouch introlab`: a small window for auditioning the intro's arrangements. Each row plays the
/// music on its own, or the whole intro with it.
final class IntroLab {
    static let shared = IntroLab()
    private var window: NSPanel?
    private let model = IntroLabModel()

    func open() {
        if window == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            p.title = "Intro Lab"
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.contentView = NSHostingView(rootView: IntroLabView(model: model))
            p.center()
            window = p
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class IntroLabModel: ObservableObject {
    @Published var playing: String?
    private var score: IntroScore?

    func music(_ a: IntroScore.Arrangement) {
        stop()
        let s = IntroScore(a)
        s.play()
        score = s
        playing = a.id
        // The piece and its tail are about nine seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self, weak s] in
            if let self, self.score === s { self.score = nil; self.playing = nil }
        }
    }

    func intro(_ a: IntroScore.Arrangement) {
        stop()
        Onboarding.shared.playIntro(a)
    }

    func stop() {
        score?.fadeOut(over: 0.3)
        score = nil
        playing = nil
    }
}

private struct IntroLabView: View {
    @ObservedObject var model: IntroLabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pick a sound for the intro").font(Theme.body(15, .medium))
                Spacer()
                Button("Stop", systemImage: "stop.fill") { model.stop() }
                    .disabled(model.playing == nil)
            }
            .padding(.horizontal, 20).padding(.top, 36).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(IntroScore.Arrangement.all) { a in row(a) }
                }
                .padding(.horizontal, 12).padding(.bottom, 16)
            }
        }
        .frame(minWidth: 460, minHeight: 360)
    }

    private func row(_ a: IntroScore.Arrangement) -> some View {
        let on = model.playing == a.id
        return HStack(spacing: 12) {
            Text(a.id).font(Theme.body(13, .medium)).monospacedDigit()
                .foregroundStyle(Theme.inkMuted).frame(width: 34, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name).font(Theme.body(13.5, .medium)).lineLimit(1)
                Text(a.blurb).textStyle(.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(on ? "Playing" : "Music", systemImage: on ? "speaker.wave.2.fill" : "music.note") { model.music(a) }
            Button("Intro", systemImage: "play.fill") { model.intro(a) }
                .help("Plays the whole intro with this music. Click anywhere to skip.")
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(on ? Theme.accentSoft : .clear))
    }
}
