import AppKit
import MinimalCatCore
import SwiftUI

/// The first run: one permission, then the five keys. It moves on by itself when the permission arrives.
@MainActor
final class Welcome {
    private let model: WelcomeModel
    private let window: NSWindow

    init(done: @escaping () -> Void) {
        model = WelcomeModel()
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 460),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.title = "Welcome to Minimal Cat"
        model.finish = { [weak window] in
            window?.close()
            done()
        }
        window.contentView = NSHostingView(rootView: WelcomeView(model: model))
    }

    func show(trusted: Bool) {
        model.step = trusted ? .keys : .permission
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func trusted() {
        guard model.step == .permission else { return }
        withAnimation(Theme.easeOut) { model.step = .keys }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class WelcomeModel: ObservableObject {
    enum Step { case permission, keys }

    @Published var step = Step.permission
    var finish: (() -> Void)?

    /// macOS 27 renamed the Accessibility pane. Name the one the user sees.
    var paneName: String {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0,
                                                                                patchVersion: 0))
            ? "Device Control and Data Access" : "Accessibility"
    }

    func openSettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "cat.fill").font(.system(size: 34)).foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            switch model.step {
            case .permission: permission
            case .keys: keys
            }
            Spacer(minLength: 0)
        }
        .padding(36)
        .frame(width: 520, height: 460, alignment: .topLeading)
        .background(Theme.surface)
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Minimal Cat moves windows only when you ask.").font(Theme.title).foregroundStyle(Theme.ink)
            Text("""
            To move and focus windows, it needs one permission. Turn on Minimal Cat in \
            Privacy & Security › \(model.paneName). This window moves on by itself.
            """)
            .font(Theme.body).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            Text("It reads no window contents and sends nothing off this Mac.")
                .font(Theme.body).foregroundStyle(Theme.inkMuted)
            Button("Open \(model.paneName)") { model.openSettings() }
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 6)
        }
    }

    private var keys: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hold the right ⌘ key. That is all.").font(Theme.title).foregroundStyle(Theme.ink)
            Text("Hold it to see every window. Hold it and press one more key to act.")
                .font(Theme.body).foregroundStyle(Theme.inkMuted)
            VStack(alignment: .leading, spacing: 10) {
                row([Command.catKey], "Tap: back to the last window")
                row([Command.catKey, "←", "→"], "Put a window on one side")
                row([Command.catKey, "↩"], "Make it big. Again puts it back")
                row([Command.catKey, "Space"], "Find a window by name")
                row([Command.catKey, "Z"], "Undo any change, also after a monitor change")
            }
            .padding(.top, 4)
            Text("The left ⌘ key works as before.")
                .font(Theme.caption).foregroundStyle(Theme.inkMuted)
            Button("Ready") { model.finish?() }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
    }

    private func row(_ keys: [String], _ text: String) -> some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { Keycap(text: $0, size: 26) }
            Text(text).font(Theme.body).foregroundStyle(Theme.ink).padding(.leading, 6)
        }
        .accessibilityElement(children: .combine)
    }
}
