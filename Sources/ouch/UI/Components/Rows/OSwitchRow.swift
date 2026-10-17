import AppKit
import SwiftUI

struct OSwitchRow: View {
    let label: String
    var description: String? = nil
    @Binding var isOn: Bool

    init(_ label: String, description: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        self.description = description
        self._isOn = isOn
    }

    var body: some View {
        ORow(label, description: description) { OSwitch(isOn: $isOn, label: label) }
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var switchRowExamples: some View {
        OSwitchRow("Focus follows mouse", description: "Hovering a window focuses it", isOn: $m.off)
        OSwitchRow("New windows go to main", description: "Instead of the end of the stack", isOn: $m.on)
    }
}
#endif
