import AppKit
import MinimalCatCore
import SwiftUI

/// `--render-previews <folder>` writes each surface as a PNG in light and dark, so a change to the UI can be
/// checked without showing a panel on the screen.
@MainActor
enum Previews {
    static func render(to folder: URL) {
        let apps = ["Calendar", "Mail", "Maps", "Notes", "Music"]
        let rows = apps.enumerated().map { index, app in
            OverlayView.Row(id: WindowID(UInt32(index + 1)), number: index + 1, title: "\(app) window", app: app,
                            icon: NSWorkspace.shared.icon(forFile: "/System/Applications/\(app).app"),
                            focused: index == 1)
        }
        let windows = apps.enumerated().map { index, app in
            WindowInfo(id: WindowID(UInt32(index + 1)), pid: 1, app: app, bundleID: nil, title: "\(app) window",
                       frame: .zero)
        }
        let icons = Dictionary(uniqueKeysWithValues: rows.compactMap { row in row.icon.map { (row.id, $0) } })
        let find = FindModel(windows: windows, icons: icons)
        let nothing = FindModel(windows: windows, icons: icons)
        nothing.query = "xcode"
        find.query = "ma"
        let surfaces: [(String, AnyView)] = [
            ("overlay", AnyView(OverlayView(rows: rows, keyName: "⇪", undo: "Z", redo: "Y"))),
            ("overlay-empty", AnyView(OverlayView(rows: [], keyName: "⇪", undo: "Z", redo: "Y"))),
            ("hud", AnyView(HUDView(text: "Put 4 windows back · ⇪ Z undoes"))),
            ("find", AnyView(FindView(model: find))),
            ("find-nothing", AnyView(FindView(model: nothing))),
            ("overlay-many", AnyView(OverlayView(rows: (0..<15).map { many(rows, $0) }, keyName: "⇪", undo: "Z",
                                                 redo: "Y"))),
            ("welcome-permission", AnyView(WelcomeView(model: welcome(.permission)))),
            ("welcome-keys", AnyView(WelcomeView(model: welcome(.keys))))
        ]
        for (name, view) in surfaces {
            for (scheme, suffix) in [(ColorScheme.light, "light"), (.dark, "dark")] {
                NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme)
                    .background(scheme == .dark ? Color(white: 0.25) : Color(white: 0.85)))
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                host.frame = CGRect(origin: .zero, size: host.fittingSize)
                let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                guard let data = rep.representation(using: .png, properties: [:]) else { continue }
                let url = folder.appendingPathComponent("\(name)-\(suffix).png")
                do { try data.write(to: url) } catch { FileHandle.standardError.write(Data("\(error)\n".utf8)) }
            }
        }
    }

    private static func many(_ rows: [OverlayView.Row], _ index: Int) -> OverlayView.Row {
        let row = rows[index % rows.count]
        return OverlayView.Row(id: WindowID(UInt32(index + 1)), number: index < 9 ? index + 1 : nil,
                               title: row.title, app: row.app, icon: row.icon, focused: index == 1)
    }

    private static func welcome(_ step: WelcomeModel.Step) -> WelcomeModel {
        let model = WelcomeModel(keyName: "Caps Lock", symbol: "⇪")
        model.step = step
        return model
    }
}
