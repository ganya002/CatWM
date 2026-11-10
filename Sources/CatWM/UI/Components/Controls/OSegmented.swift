import AppKit
import CatWMKit
import SwiftUI

struct OSegmented<T: Hashable>: View {
    let title: String
    let options: [OSegmentOption<T>]
    private let isOn: (T) -> Bool
    private let pick: (T) -> Void
    private let multiple: Bool
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            ForEach(options, id: \.value) { option in
                OSegment(label: option.label, keys: option.keys, count: option.count, selected: isOn(option.value),
                         thumb: multiple ? nil : thumb) {
                    withAnimation(reduceMotion ? Motion.fade : Motion.spring) { pick(option.value) }
                }
                .tooltip(option.help ?? "")
                .accessibilityLabel(option.help ?? option.label)
                .accessibilityAddTraits(multiple ? .isToggle : [])
            }
        }
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var segmentExamples: some View {
        OSegmented(title: "Curve", options: ["Ease", "Spring", "Off"].map { ($0, $0) }, selection: $model.segment)
    }
}
#endif

struct OSegmentOption<T: Hashable> {
    let value: T
    var label: String
    var keys: String?
    var count: Int?
    var help: String?
}
