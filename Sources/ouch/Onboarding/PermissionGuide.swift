// Onboarding: the panel beside System Settings that guides the Accessibility grant.
import AppKit
import SwiftUI

/// A small floating panel that sits beside System Settings while the Accessibility list is open,
/// telling the user what to click. Follows the Settings window, offers the app icon to drag into
/// the list, and closes itself once the permission is granted.
final class PermissionGuide {
    static let shared = PermissionGuide()
    private var panel: NSPanel?
    private var host: NSView?
    private var follow: Timer?
    private let model = GuideModel()
    /// Which permission the guide is walking through.
    private(set) var kind = Permission.accessibility
    private let gap: CGFloat = 12

    var isShowing: Bool { (panel?.isVisible ?? false) && (panel?.alphaValue ?? 0) > 0 }
    /// We opened System Settings for the grant and haven't cleaned up yet; stays set when the guide is
    /// hidden, so Settings and macOS's alert still go away once access is granted.
    private var pending = false
    private var finishing = false
    private var hidden = false     // the user clicked Hide
    private var sawSettings = false
    private var sawAlert = false
    private var missingTicks = 0
    private var waitTicks = 0
    /// What the guide sits beside, and how long it has stayed put. The guide only moves to a target
    /// that has settled, so it doesn't hop along while Settings opens or is being dragged.
    private var target: NSRect?
    private var steadyTicks = 0
    private var placed: NSRect?    // the frame we last gave the panel
    private var userMoved = false  // dragged by the user: stop following, only resize
    private var movedAt = Date.distantPast // our last move; the frame is in flux right after it

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
        // Appears from tick() once the alert or Settings is up and has settled, right where it belongs.
        if isShowing { update(snap) }
        follow?.invalidate()
        follow = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        follow?.tolerance = 0.04 // coalesces with other wakeups
    }

    /// Hides the panel; a pending grant is still watched (see `granted()`).
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

    /// Called when the permission turns on (by the watchdog and by our own timer, so it runs once):
    /// flip to a checkmark, then clear away the guide, macOS's alert and the Settings window.
    func granted(_ granted: Permission = .accessibility) {
        guard pending, !finishing, granted == kind else { return }
        finishing = true
        follow?.invalidate()
        follow = nil
        model.granted = true
        layout(animated: true, afterFade: true) // shrink to the short "All set" content, top edge in place
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self else { return }
            finishing = false
            guard kind.isGranted else { // turned off again meanwhile: back to guiding
                model.granted = false
                layout(animated: true)
                follow = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
                follow?.tolerance = 0.04 // coalesces with other wakeups
                return
            }
            stop()
            Permission.dismissSystemAlert()
            // The alert's button brings Settings forward; close it after that lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Permission.closeSettingsWindows() }
            onGranted?()
        }
    }

    /// Runs after a grant has been cleaned up (the onboarding card comes back to the front).
    var onGranted: (() -> Void)?

    private func tick() {
        if kind.isGranted { granted(kind); return }
        let snap = Snapshot()
        // System Settings was closed (or macOS's alert denied) without granting: don't leave the guide
        // floating on its own.
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
        // While macOS's alert is up the steps point at it, so sit beside it rather than Settings.
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
            // Appear once there's a settled target, or after a second and a half without one.
            if (target != nil && steadyTicks >= 1) || waitTicks >= 8 { appear() }
            return
        }
        if let placed, Date().timeIntervalSince(movedAt) > 0.5,
           abs(panel.frame.minX - placed.minX) > 1 || abs(panel.frame.maxY - placed.maxY) > 1 { userMoved = true }
        // Follow a target once it has settled; when it's gone (closing), stay put.
        if contentChanged { layout(animated: true, afterFade: true) }
        else if steadyTicks == 1 && target != nil { layout(animated: true) }
    }

    // MARK: Placement

    /// The frame for the current content beside the current target.
    private func desiredFrame() -> NSRect {
        let size = host?.fittingSize ?? panel?.frame.size ?? .zero
        if let cur = panel?.frame, isShowing, userMoved || target == nil {
            return NSRect(x: cur.minX, y: cur.maxY - size.height, width: size.width, height: size.height)
        }
        guard let t = target else {
            // Nothing to sit beside: wait near the right edge of the main display.
            let area = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            return NSRect(x: area.maxX - size.width - 40, y: area.midY - size.height / 2, width: size.width, height: size.height)
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(t) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        var o = NSPoint(x: t.maxX + gap, y: t.maxY - size.height)
        if o.x + size.width > area.maxX { o.x = t.minX - gap - size.width } // no room on the right
        if o.x < area.minX { o.x = area.maxX - size.width - gap }           // no room either side
        o.y = min(max(o.y, area.minY), area.maxY - size.height)
        return NSRect(origin: o, size: size).integral
    }

    /// One move for size and position together, so they never fight. New content cross-fades for 0.2s
    /// and measures as both states at once until then, so `afterFade` waits for it to finish.
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
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1)
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
        let frame = desiredFrame() // while not showing, so it's beside the target, not where it last was
        placed = frame
        movedAt = Date()
        panel.setFrame(frame.offsetBy(dx: 0, dy: -6), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
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
            // Shown again meanwhile? Then leave it.
            if self?.pending == false || self?.hidden == true { panel.orderOut(nil) }
        })
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 10),
                        styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                        backing: .buffered, defer: false)
        p.clearTitlebar(hiding: [.closeButton, .miniaturizeButton, .zoomButton])
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.level = .floating
        // Not in the window cycle, like the other panels.
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: GuideView(model: model, dismiss: { [weak self] in self?.hide() }))
        host.sizingOptions = [.intrinsicContentSize] // measured by fittingSize; layout() applies it in one move
        // The hidden title bar's safe area would otherwise count toward fittingSize, leaving a blank strip
        // under the buttons.
        host.safeAreaRegions = []
        if #available(macOS 26.0, *) {
            // A floating glass panel: the window itself goes clear and the glass draws the shape.
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

    // MARK: What's on screen

    /// macOS's "would like to control this computer" alert, if it's on screen (AppKit coordinates).
    /// Readable without Accessibility: only its owner and bounds are needed.
    static func alertFrame() -> NSRect? { Snapshot().alert }

    /// The alert and the frontmost System Settings window, from one look at the window list.
    private struct Snapshot {
        var alert: NSRect?
        var settings: NSRect?

        init() {
            guard let primary = NSScreen.screens.first,
                  let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
            else { return }
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.accessibility.universalAccessAuthWarn").first?.processIdentifier
            // By process, not name: the owner name is localized ("Systemindstillinger", …).
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
    /// macOS's own alert is up; its button is what adds Ouch to the list.
    @Published var alertUp = false
}

/// Steps beside System Settings: numbered rows, the app to drag in, and a quiet waiting line.
private struct GuideView: View {
    @ObservedObject var model: GuideModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.granted {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.success)
                        .transition(.symbolEffect(.appear))
                    Text("All set").font(Theme.body(22)).oneLine()
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accentInk)
                        Text(model.kind.title).kicker()
                    }
                    Text("Allow Ouch").font(Theme.body(22)).tracking(-0.2).oneLine().padding(.top, 6)
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
                    Text("Waiting…").font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine()
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
        .ignoresSafeArea() // the title bar is invisible (no traffic lights), so don't reserve room for it
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
        // Only the app's location. Offering its contents (NSItemProvider(contentsOf:)) let Settings take
        // a copy of the bundle, so the switch turned on a copy and this app never became trusted.
        .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
        .tooltip("Drag into the \(model.kind.title) list")
    }
}
