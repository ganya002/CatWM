import AppKit
import CatWMKit
import SwiftUI

struct SearchResults: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI

    var body: some View {
        let results = SettingsIndex.search(settingsUI.search, doc: doc)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.small) {
                    Text("Search").textStyle(.title).foregroundStyle(Theme.ink).oneLine()
                    Text("“\(settingsUI.search)”").font(Theme.body(15)).foregroundStyle(Theme.inkMuted).oneLine()
                }
                .accessibilityAddTraits(.isHeader)
                if results.isEmpty {
                    Text("Nothing matches. Try another word, like “gaps” or “focus”.")
                        .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).oneLine()
                }
                ForEach(Pane.allCases) { pane in
                    let here = results.filter { $0.pane == pane }
                    if !here.isEmpty {
                        OGroup(pane.rawValue) {
                            ForEach(here) { result in
                                ResultRow(entry: result, first: result.id == results.first?.id) {
                                    settingsUI.open(result)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.extraLarge).padding(.top, 22).padding(.bottom, 40)
            .frame(maxWidth: 660, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ResultRow: View {
    let entry: SettingEntry
    let first: Bool
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.medium) {
                Image(systemName: entry.bind != nil ? "command" : entry.pane.icon)
                    .font(Theme.symbol()).foregroundStyle(Theme.inkMuted).frame(width: 18)
                Text(entry.title).font(Theme.body()).oneLine()
                if entry.advanced {
                    Text("Advanced").textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                }
                Spacer(minLength: 8)
                if first { Text("↩").font(Theme.keys(12)).foregroundStyle(Theme.inkMuted) }
                Image(systemName: "arrow.right").font(Theme.symbol(Theme.Icon.small, .semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .opacity(hover.isOn ? 1 : 0)
            }
            .padding(.horizontal, Theme.Space.medium).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(hover.isOn ? Theme.hover : .clear))
            .padding(.horizontal, -Theme.Space.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
    }
}
