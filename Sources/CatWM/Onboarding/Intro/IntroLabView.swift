import AppKit
import CatWMKit
import SwiftUI

struct IntroLabView: View {
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
                    ForEach(IntroScore.Arrangement.all) { row($0) }
                }
                .padding(.horizontal, 12).padding(.bottom, 16)
            }
        }
        .frame(minWidth: 460, minHeight: 360)
    }

    private func row(_ arrangement: IntroScore.Arrangement) -> some View {
        let playing = model.playing == arrangement.id
        return HStack(spacing: 12) {
            Text(arrangement.id).font(Theme.body(13, .medium)).monospacedDigit()
                .foregroundStyle(Theme.inkMuted).frame(width: 34, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(arrangement.name).font(Theme.body(13.5, .medium)).lineLimit(1)
                Text(arrangement.blurb).textStyle(.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(playing ? "Playing" : "Music", systemImage: playing ? "speaker.wave.2.fill" : "music.note") {
                model.music(arrangement)
            }
            Button("Intro", systemImage: "play.fill") { model.intro(arrangement) }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(playing ? Theme.accentSoft : .clear)
        )
    }
}

final class IntroLab {
    static let shared = IntroLab()
    private var window: NSPanel?
    private let model = IntroLabModel()

    func open() {
        if window == nil {
            let rect = NSRect(x: 0, y: 0, width: 520, height: 640)
            let style: NSWindow.StyleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            let panel = NSPanel( // style-ok: debug intro lab window
                contentRect: rect, styleMask: style, backing: .buffered, defer: false)
            panel.title = "Intro Lab"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: IntroLabView(model: model))
            panel.center()
            window = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class IntroLabModel: ObservableObject {
    @Published var playing: String?
    private var score: IntroScore?

    func music(_ arrangement: IntroScore.Arrangement) {
        stop()
        let started = IntroScore(arrangement)
        started.play()
        score = started
        playing = arrangement.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self, weak started] in
            if let self, self.score === started { self.score = nil; self.playing = nil }
        }
    }

    func intro(_ arrangement: IntroScore.Arrangement) {
        stop()
        Onboarding.shared.playIntro(arrangement)
    }

    func stop() {
        score?.fadeOut(over: 0.3)
        score = nil
        playing = nil
    }
}
