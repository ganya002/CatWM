import AppKit
import SwiftUI

struct SortStrategies: View {
    let selection: SortStrategy?
    let pick: (SortStrategy) -> Void

    var body: some View {
        OSegmented(title: "Group by", options: SortStrategy.allCases.map { OSegmentOption(value: $0, label: $0.title) },
                   selection: selection, pick: pick)
    }
}
