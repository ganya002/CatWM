import AppKit
import SwiftUI

final class PermissionGuide {
    static let shared = PermissionGuide()
    private var panel: NSPanel?
    private var host: NSView?
    private var follow: Timer?
    private let model = GuideModel()
    private(set) var kind = Permission.accessibility
    private let gap: CGFloat = 12

    var isShowing: Bool { (panel?.isVisible ?? false) && (panel?.alphaValue ?? 0) > 0 }
    private var pending = false
    private var finishing = false
    private var hidden = false
    private var sawSettings = false
    private var sawAlert = false
    private var missingTicks = 0
    private var waitTicks = 0
    private var target: NSRect?
    private var steadyTicks = 0
    private var placed: NSRect?
    private var userMoved = false
    private var movedAt = Date.distantPast

    func show(_ kind: Permission = .accessibility) {
        self.kind = kind
        model.kind = kind
        finishing = false
        pending = true
        hidden = false
        sawSettings = false
        sawAlert = false
        missingTicks = 0
        waitTicks = 0
        steadyTicks = 0
        target = nil
        userMoved = false
        if panel == nil { panel = makePanel() }
        let snap = Snapshot()
        model.granted = false
        model.alertUp = snap.alert != nil
        if isShowing { update(snap) }
        follow?.invalidate()
        follow = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        follow?.tolerance = 0.04
    }

    func hide() {
        hidden = true
        fadeOut()
    }

    private func stop() {
        follow?.invalidate()
        follow = nil
        pending = false
        fadeOut()
    }

    func granted(_ granted: Permission = .accessibility) {
        guard pending, !finishing, granted == kind else { return }
        finishing = true
        follow?.invalidate()
        follow = nil
        model.granted = true
        layout(animated: true, afterFade: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self else { return }
            finishing = false
            guard kind.isGranted else {
                model.granted = false
                layout(animated: true)
                follow = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
                follow?.tolerance = 0.04
                return
            }
            stop()
            Permission.dismissSystemAlert()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Permission.closeSettingsWindows() }
            onGranted?()
        }
    }

    var onGranted: (() -> Void)?

    private func tick() {
        if kind.isGranted { granted(kind); return }
        let snap = Snapshot()
        if snap.alert != nil { sawAlert = true }
        if snap.settings != nil && snap.alert == nil { sawSettings = true }
        if snap.alert != nil || snap.settings != nil {
            missingTicks = 0
        } else if sawSettings || sawAlert {
            missingTicks += 1
            if missingTicks >= (sawSettings ? 5 : 10) { stop(); return }
        }
        update(snap)
    }

    private func update(_ snap: Snapshot) {
        let alertUp = snap.alert != nil
        let contentChanged = model.alertUp != alertUp
        if contentChanged { model.alertUp = alertUp }
        let t = snap.alert ?? snap.settings
        if t.map({ old in target.map { $0.equalTo(old) } ?? false }) ?? (target == nil) {
            steadyTicks += 1
        } else {
            target = t
            steadyTicks = 0
        }
        guard !hidden, let panel else { return }
        if !isShowing {
            waitTicks += 1
            if (target != nil && steadyTicks >= 1) || waitTicks >= 8 { appear() }
            return
        }
        if let placed, Date().timeIntervalSince(movedAt) > 0.5,
           abs(panel.frame.minX - placed.minX) > 1 || abs(panel.frame.maxY - placed.maxY) > 1 { userMoved = true }
        if contentChanged { layout(animated: true, afterFade: true) }
        else if steadyTicks == 1 && target != nil { layout(animated: true) }
    }

    private func desiredFrame() -> NSRect {
        let size = host?.fittingSize ?? panel?.frame.size ?? .zero
        if let cur = panel?.frame, isShowing, userMoved || target == nil {
            return NSRect(x: cur.minX, y: cur.maxY - size.height, width: size.width, height: size.height)
        }
        guard let t = target else {
            let area = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            return NSRect(x: area.maxX - size.width - 40, y: area.midY - size.height / 2, width: size.width, height: size.height)
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(t) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        var o = NSPoint(x: t.maxX + gap, y: t.maxY - size.height)
        if o.x + size.width > area.maxX { o.x = t.minX - gap - size.width }
        if o.x < area.minX { o.x = area.maxX - size.width - gap }
        o.y = min(max(o.y, area.minY), area.maxY - size.height)
        return NSRect(origin: o, size: size).integral
    }

    private func layout(animated: Bool, afterFade: Bool = false) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (afterFade ? 0.22 : 0)) { [weak self] in
            guard let self, let panel else { return }
            let frame = desiredFrame()
            placed = frame
            guard !frame.equalTo(panel.frame) else { return }
            movedAt = Date()
            if animated && panel.isVisible {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.28
                    ctx.timingFunction = Motion.Curve.settle
                    panel.animator().setFrame(frame, display: true)
                }
            } else {
                panel.setFrame(frame, display: true)
            }
        }
    }

    private func appear() {
        guard let panel else { return }
        panel.alphaValue = 0
        let frame = desiredFrame()
        placed = frame
        movedAt = Date()
        panel.setFrame(frame.offsetBy(dx: 0, dy: -6), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = Motion.Curve.fade
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func fadeOut() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.pending == false || self?.hidden == true { panel.orderOut(nil) }
        })
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 10), // style-ok: titled glass permission guide
                        styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                        backing: .buffered, defer: false)
        p.clearTitlebar(hiding: [.closeButton, .miniaturizeButton, .zoomButton])
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: GuideView(model: model, dismiss: { [weak self] in self?.hide() }))
        host.sizingOptions = [.intrinsicContentSize]
        host.safeAreaRegions = []
        if #available(macOS 26.0, *) {
            p.isOpaque = false
            p.backgroundColor = .clear
            let glass = NSGlassEffectView()
            glass.cornerRadius = Theme.Radius.xl
            glass.contentView = host
            p.contentView = glass
        } else {
            p.backgroundColor = Theme.ns(\.surfaceRaised)
            p.contentView = host
        }
        p.setContentSize(host.fittingSize)
        self.host = host
        return p
    }

    static func alertFrame() -> NSRect? { Snapshot().alert }

    private struct Snapshot {
        var alert: NSRect?
        var settings: NSRect?

        init() {
            guard let primary = NSScreen.screens.first,
                  let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
            else { return }
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.accessibility.universalAccessAuthWarn").first?.processIdentifier
            let settingsPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.processIdentifier
            for info in list {
                guard let pid = (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init), pid == agent || pid == settingsPID,
                      let dict = info[kCGWindowBounds as String] as? NSDictionary,
                      let r = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
                let frame = NSRect(x: r.minX, y: primary.frame.maxY - r.maxY, width: r.width, height: r.height)
                if pid == agent, alert == nil, r.width > 150, r.height > 80 { alert = frame }
                if pid == settingsPID, settings == nil, (info[kCGWindowLayer as String] as? Int) == 0, r.width > 200 { settings = frame }
            }
        }
    }
}

private final class GuideModel: ObservableObject {
    @Published var granted = false
    @Published var kind = Permission.accessibility
    @Published var alertUp = false
}

private struct GuideView: View {
    @ObservedObject var model: GuideModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.granted {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(Theme.symbol(Theme.Icon.xl, .regular)).foregroundStyle(Theme.success)
                        .transition(.symbolEffect(.appear))
                    Text("All set").textStyle(.title).oneLine()
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open").font(Theme.symbol()).foregroundStyle(Theme.accentInk)
                        Text(model.kind.title).kicker()
                    }
                    Text("Allow Ouch").textStyle(.title).oneLine().padding(.top, 6)
                    Text(model.alertUp ? "macOS asks first, then System Settings opens." : "Follow these steps in System Settings.")
                        .font(Theme.body(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 10) {
                    if model.alertUp {
                        OStep(n: 1, text: "In the macOS alert, click **Open System Settings**.")
                        OStep(n: 2, text: "Turn its switch **on**. Enter your password if asked.")
                    } else {
                        OStep(n: 1, text: "Find **Ouch** in the \(model.kind.title) list.")
                        OStep(n: 2, text: "Turn its switch **on**. Enter your password if asked.")
                        OStep(n: 3, text: "Not in the list? Click **+**, or drag this icon into it:")
                    }
                }
                if !model.alertUp { dragTile }

                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                    Text("Waiting…").textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                    Spacer(minLength: 4)
                    OButton("Reset", variant: .ghost, size: .sm) {
                        model.kind.reset()
                    }
                    .tooltip("Clears a stale entry left by a rebuilt or moved copy of the app")
                    OButton("Hide", size: .sm, action: dismiss)
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        .foregroundStyle(Theme.ink)
        .ignoresSafeArea()
        .animation(Motion.easeOut, value: model.granted)
        .animation(Motion.easeOut, value: model.alertUp)
    }

    private var dragTile: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
            Text("Ouch").font(Theme.body(14, .medium))
            Spacer()
            Image(systemName: "hand.draw").foregroundStyle(Theme.inkMuted)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(Theme.well))
        .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
        .tooltip("Drag into the \(model.kind.title) list")
    }
}
