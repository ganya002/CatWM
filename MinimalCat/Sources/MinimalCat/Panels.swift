import AppKit
import SwiftUI

/// A borderless floating panel that holds one SwiftUI view. Only the find panel takes key focus.
final class FloatingPanel: NSPanel {
    private let takesKey: Bool

    init(takesKey: Bool = false) {
        self.takesKey = takesKey
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { takesKey }
    override var canBecomeMain: Bool { false }

    func show<Content: View>(_ content: Content, on screen: NSScreen?, at placement: Placement) {
        let host = NSHostingView(rootView: content)
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
        let size = host.fittingSize
        let area = (screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let origin: CGPoint = switch placement {
        case .center: CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2 + area.height * 0.08)
        case .bottom: CGPoint(x: area.midX - size.width / 2, y: area.minY + area.height * 0.12)
        case .top: CGPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - area.height * 0.18)
        }
        setFrame(CGRect(origin: origin, size: size).integral, display: true)
        alphaValue = 1
        orderFrontRegardless()
        if takesKey { makeKey() }
    }

    enum Placement { case center, bottom, top }
}

/// The screen that holds the focused window, or else the pointer.
func activeScreen() -> NSScreen? {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
}

// MARK: - HUD

/// A one-line notice: what changed and how to undo it. Read aloud under VoiceOver.
@MainActor
final class HUD {
    private let panel = FloatingPanel()
    private var hide: DispatchWorkItem?

    func show(_ text: String) {
        hide?.cancel()
        panel.show(HUDView(text: text), on: activeScreen(), at: .bottom)
        let work = DispatchWorkItem { [panel] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Theme.fast
                panel.animator().alphaValue = 0
            } completionHandler: { panel.orderOut(nil) }
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }
}

struct HUDView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .floatingCard(radius: 22)
            .padding(30)
    }
}
