import AppKit
import SwiftUI

struct OSectionHeader: View {
    let title: String
    var tone: Color = Theme.ink
    var dot: Color?

    init(_ title: String, tone: Color = Theme.ink, dot: Color? = nil) {
        self.title = title; self.tone = tone; self.dot = dot
    }

    var body: some View {
        HStack(spacing: 7) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            Text(title).textStyle(.sectionTitle).foregroundStyle(tone).oneLine()
        }
        .accessibilityAddTraits(.isHeader)
    }
}
