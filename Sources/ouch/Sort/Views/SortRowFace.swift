import AppKit
import SwiftUI

struct SortRowFace: View {
    let item: SortItem
    let closing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.extraSmall, style: .continuous).fill(Theme.tint)
                        .overlay(Text(String(item.app.prefix(1)))
                            .font(Theme.body(10.5, .medium)).foregroundStyle(Theme.ink))
                }
            }
            .frame(width: 20, height: 20)
            (Text(item.title).foregroundColor(closing ? Theme.inkMuted : Theme.ink)
                + Text(item.title.localizedCaseInsensitiveContains(item.app) ? "" : "  " + item.app)
                    .textStyle(.caption).foregroundColor(Theme.inkFaint))
                .strikethrough(closing, color: Theme.danger)
                .oneLine()
            Spacer(minLength: 0)
        }
        .font(Theme.body(13.5))
    }
}
