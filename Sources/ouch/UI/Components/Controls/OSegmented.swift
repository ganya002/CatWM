import AppKit
import SwiftUI

struct OSegmented<T: Hashable>: View {
    let title: String
    let options: [OSegmentOption<T>]
    private let isOn: (T) -> Bool
    private let pick: (T) -> Void
    private let multiple: Bool
    @Namespace private var thumb

    init(title: String, options: [(value: T, label: String)], selection: Binding<T>) {
        self.title = title
        self.options = options.map { OSegmentOption(value: $0.value, label: $0.label) }
        isOn = { $0 == selection.wrappedValue }
        pick = { selection.wrappedValue = $0 }
        multiple = false
    }

    init(title: String, options: [OSegmentOption<T>], selection: T?, pick: @escaping (T) -> Void) {
        self.title = title
        self.options = options
        isOn = { $0 == selection }
        self.pick = pick
        multiple = false
    }

    init(title: String, options: [OSegmentOption<T>], isOn: @escaping (T) -> Bool, toggle: @escaping (T) -> Void) {
        self.title = title
        self.options = options
        self.isOn = isOn
        pick = toggle
        multiple = true
    }

    var body: some View {
        OSegmentTrack(title: title) {
            ForEach(options, id: \.value) { o in
                OSegment(label: o.label, keys: o.keys, count: o.count, on: isOn(o.value), thumb: multiple ? nil : thumb) {
                    withAnimation(Motion.spring) { pick(o.value) }
                }
                .tooltip(o.help ?? "")
                .accessibilityLabel(o.help ?? o.label)
                .accessibilityAddTraits(multiple ? .isToggle : [])
            }
        }
    }
}
