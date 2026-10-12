import AppKit
import SwiftUI

/// A small floating panel that sits beside System Settings while the Accessibility list is open,
/// telling the user what to click. Follows the Settings window, offers the app icon to drag into
/// the list, and closes itself once the permission is granted.
final class PermissionGuide {
    static let shared = PermissionGuide()
    private var panel: NSPanel?
    private var follow: Timer?
    private let model = GuideModel()
    private let gap: CGFloat = 12

    var isShowing: Bool { panel?.isVisible ?? false }

    func show() {
        model.granted = false
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        reposition(animated: false)
        panel.orderFrontRegardless()
        follow?.invalidate()
        follow = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    func hide() {
        follow?.invalidate()
        follow = nil
        panel?.orderOut(nil)
    }

    /// Called when Accessibility turns on: flip to a checkmark, then get out of the way.
    func granted() {
        guard isShowing else { return }
        model.granted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard AXIsProcessTrusted() else { return }
            self?.hide()
            Permissions.closeSettingsWindows()
        }
    }

    private func tick() {
        if AXIsProcessTrusted() { granted(); follow?.invalidate(); follow = nil; return }
        reposition(animated: true)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 10),
                        styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                        backing: .buffered, defer: false)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            p.standardWindowButton(button)?.isHidden = true
        }
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: GuideView(model: model, dismiss: { [weak self] in self?.hide() }))
        host.sizingOptions = [.intrinsicContentSize]
        p.contentView = host
        p.setContentSize(host.fittingSize)
        return p
    }

    /// Frame of the frontmost System Settings window in AppKit (bottom-left origin) coordinates.
    private func settingsFrame() -> NSRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerName as String] as? String) == "System Settings",
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict as CFDictionary), r.width > 200 else { continue }
            return NSRect(x: r.minX, y: primary.frame.maxY - r.maxY, width: r.width, height: r.height)
        }
        return nil
    }

    private func reposition(animated: Bool) {
        guard let panel else { return }
        let size = panel.frame.size
        var origin: NSPoint
        if let target = settingsFrame() {
            let screen = NSScreen.screens.first { $0.frame.intersects(target) } ?? NSScreen.main ?? NSScreen.screens[0]
            let area = screen.visibleFrame
            let top = target.maxY - size.height
            origin = NSPoint(x: target.maxX + gap, y: top)
            if origin.x + size.width > area.maxX { origin.x = target.minX - gap - size.width } // no room on the right
            if origin.x < area.minX { origin.x = area.maxX - size.width - gap }                 // no room either side
            origin.y = min(max(origin.y, area.minY), area.maxY - size.height)
        } else {
            // System Settings isn't up yet: wait near the right edge of the main display.
            let area = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            origin = NSPoint(x: area.maxX - size.width - 40, y: area.midY - size.height / 2)
        }
        let frame = NSRect(origin: origin, size: size)
        if abs(frame.minX - panel.frame.minX) < 1, abs(frame.minY - panel.frame.minY) < 1 { return }
        panel.setFrame(frame, display: true, animate: animated && panel.isVisible)
    }
}

private final class GuideModel: ObservableObject {
    @Published var granted = false
}

private struct GuideView: View {
    @ObservedObject var model: GuideModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.granted {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All set").font(.headline)
                        Text("mxtiler now has Accessibility access.").font(.callout).foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Allow mxtiler").font(.headline)
                    Text("Follow these steps in System Settings.").font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    row(1, "Find **mxtiler** in the Accessibility list.")
                    row(2, "Turn its switch **on**. Enter your password if asked.")
                    row(3, "Not in the list? Click **+**, or drag this icon into it:")
                }
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                    Text("mxtiler").font(.callout.weight(.medium))
                    Spacer()
                    Image(systemName: "hand.draw").foregroundStyle(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))
                .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider() }
                .help("Drag into the Accessibility list")

                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for permission…").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { Permissions.reset() }
                        .help("Clears a stale entry left by a rebuilt or moved copy of the app")
                    Button("Hide", action: dismiss)
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 300)
        .animation(.default, value: model.granted)
    }

    private func row(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Color.accentColor))
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}
