import AppKit
import SwiftUI

struct OPageTitle<Trailing: View>: View {
    let crumbs: [String]
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(crumbs.enumerated()), id: \.offset) { i, c in
                    if i > 0 { Image(systemName: "chevron.right").font(Theme.symbol(Theme.Icon.xs, .semibold)) }
                    Text(c)
                }
            }
            .textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
            HStack(alignment: .center, spacing: Theme.Space.sm) {
                Text(title).textStyle(.largeTitle).oneLine()
                Spacer(minLength: Theme.Space.md)
                trailing
            }
        }
    }
}
