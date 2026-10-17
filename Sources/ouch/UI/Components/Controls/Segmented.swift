import AppKit
import SwiftUI

struct OSegmentOption<T: Hashable> {
    let value: T
    var label: String
    var keys: String? = nil
    var count: Int? = nil
    var help: String? = nil
}

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

struct OSegmentTrack<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Theme.Space.xxs) { content }
            .padding(3)
            .background(Capsule().fill(Theme.well))
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
    }
}

struct OSegment<Lead: View>: View {
    let label: String
    var keys: String? = nil
    var count: Int? = nil
    let on: Bool
    var hot = false
    var thumb: Namespace.ID? = nil
    let action: () -> Void
    @ViewBuilder var lead: (Color) -> Lead

    var body: some View {
        let ink = on ? Theme.onAccent : hot ? Theme.accentInk : Theme.inkMuted
        Button(action: action) {
            HStack(spacing: 5) {
                lead(ink)
                if let keys { Text(keys).font(Theme.keys(12.5, .medium)) }
                if !label.isEmpty { Text(label).font(Theme.body(12.5, on ? .medium : .regular)).oneLine() }
                if let count {
                    Text("\(count)").font(Theme.body(12)).monospacedDigit()
                        .foregroundStyle(on ? Theme.onAccent.opacity(0.8) : Theme.inkFaint)
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, label.isEmpty ? 9 : 12).frame(height: 24)
            .background {
                if on {
                    if let thumb { Capsule().fill(Theme.accent).matchedGeometryEffect(id: "thumb", in: thumb) }
                    else { Capsule().fill(Theme.accent) }
                } else if hot {
                    Capsule().fill(Theme.accentSoft)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

extension OSegment where Lead == EmptyView {
    init(label: String, keys: String? = nil, count: Int? = nil, on: Bool, hot: Bool = false, thumb: Namespace.ID? = nil,
         action: @escaping () -> Void) {
        self.init(label: label, keys: keys, count: count, on: on, hot: hot, thumb: thumb, action: action) { _ in EmptyView() }
    }
}
