import AppKit
import SwiftUI

struct ORow<Control: View>: View {
    let label: String
    var description: String? = nil
    var symbol: String? = nil
    @ViewBuilder var control: Control
    @Environment(\.isEnabled) private var enabled

    init(_ label: String, description: String? = nil, symbol: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.description = description
        self.symbol = symbol
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).font(Theme.symbol(Theme.Icon.lg)).foregroundStyle(Theme.accentInk)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(Theme.body(14)).foregroundStyle(Theme.ink).oneLine()
                if let description {
                    Text(description).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                }
            }
            .opacity(enabled ? 1 : 0.45)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { control }.fixedSize()
        }
        .frame(minHeight: 48)
        .padding(.vertical, 8)
    }
}

extension ORow where Control == EmptyView {
    init(_ label: String, description: String? = nil, symbol: String? = nil) {
        self.init(label, description: description, symbol: symbol) { EmptyView() }
    }
}

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

struct OSectionHeader: View {
    let title: String
    var tone: Color = Theme.accentInk
    var dot: Color? = nil

    init(_ title: String, tone: Color = Theme.accentInk, dot: Color? = nil) {
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
