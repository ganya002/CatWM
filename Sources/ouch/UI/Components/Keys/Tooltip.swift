import AppKit
import SwiftUI

struct OTooltip: View {
    static let delay = 0.5
    let text: String
    var chords: [[String]] = []
    var caret: Caret = .bottom

    var body: some View {
        HStack(spacing: 10) {
            Text(text).font(Theme.body(12.5)).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320, alignment: .leading)
            if !chords.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(chords.enumerated()), id: \.offset) { i, keys in
                        if i > 0 { Text("then").font(Theme.body(11.5)).foregroundStyle(Theme.inkMuted).oneLine() }
                        Kbd(keys: keys)
                    }
                }
                .fixedSize()
            }
        }
        .surface(.xs, caret: caret)
        .accessibilityElement(children: .combine)
    }
}
