import AppKit
import SwiftUI

struct OMenuRowBody: View {
    let configuration: ButtonStyleConfiguration
    let style: OMenuRowStyle
    @StateObject private var hover = Flag()
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let lit = enabled && style.highlight.isLit(hovering: hover.isOn)
        let fill: Color = configuration.isPressed ? Theme.wellHover
            : lit ? (style.danger ? Theme.dangerSoft : Theme.hover)
            : style.open ? Theme.wellHover : .clear
        Group {
            if style.bare {
                configuration.label
            } else {
                configuration.label
                    .padding(.horizontal, OMenuRowStyle.inset)
                    .frame(maxWidth: .infinity, minHeight: Theme.rowHeight, maxHeight: Theme.rowHeight,
                           alignment: .leading)
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(fill))
        .contentShape(Rectangle())
        .onHover { hover.isOn = $0 }
    }
}
