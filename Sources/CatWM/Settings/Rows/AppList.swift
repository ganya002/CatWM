import AppKit
import CatWMKit
import SwiftUI

struct AppList: View {
    @Binding var ids: [String]
    var title: String?
    let empty: String

    var body: some View {
        if let title {
            ORow(title, description: empty) { addMenu }
            rows
        } else if ids.isEmpty {
            ORow("No apps yet", description: empty) { addMenu }
        } else {
            HStack { addMenu; Spacer() }.padding(.vertical, Theme.Space.small)
            rows
        }
    }

    private var rows: some View {
        ForEach(ids, id: \.self) { id in
            HStack(spacing: 12) {
                Self.icon(id)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.name(id) ?? id).font(Theme.body()).oneLine()
                    if Self.name(id) != nil {
                        Text(id).font(Theme.mono(11, .regular)).foregroundStyle(Theme.inkMuted)
                            .oneLine(.middle)
                    }
                }
                Spacer(minLength: 0)
                RemoveButton(help: "Remove \(Self.name(id) ?? id)") {
                    withAnimation(Motion.easeOut) { ids.removeAll { $0 == id } }
                }
            }
            .frame(minHeight: 48).padding(.vertical, 6)
        }
    }

    private var addMenu: some View {
        let ids = $ids
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .compactMap { app in app.bundleIdentifier.map { (name: app.localizedName ?? $0, id: $0, icon: app.icon) } }
            .filter { !ids.wrappedValue.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return OMenuButton(style: OButtonStyle(variant: .secondary, size: .small), items: {
            apps.map { app in
                MenuItem(id: app.id, label: app.name, image: app.icon.map(Self.resized), action: {
                    if !ids.wrappedValue.contains(app.id) {
                        withAnimation(Motion.easeOut) { ids.wrappedValue.append(app.id) }
                    }
                })
            }
        }, label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(Theme.symbol(Theme.Icon.small))
                Text("Add Running App")
            }
        })
        .fixedSize()
    }

    private static func resized(_ image: NSImage) -> NSImage {
        guard let copy = image.copy() as? NSImage else { return image }
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    private static func url(_ id: String) -> URL? {
        id.hasSuffix("*") ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    private static func name(_ id: String) -> String? {
        url(id).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }

    @ViewBuilder private static func icon(_ id: String) -> some View {
        if let url = url(id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .frame(width: 26, height: 26).padding(1)
        }
    }
}
