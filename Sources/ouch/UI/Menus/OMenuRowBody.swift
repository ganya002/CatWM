import AppKit
import SwiftUI

struct OMenuRowBody: View {
    let configuration: ButtonStyleConfiguration
    let style: OMenuRowStyle
    @StateObject private var hover = Flag()

    var body: some View {
        let lit = style.highlighted ?? hover.on
        let fill: Color = configuration.isPressed ? Theme.wellHover
            : lit ? (style.danger ? Theme.dangerSoft : Theme.well)
            : style.open ? Theme.wellHover : .clear
        Group {
            if style.bare {
                configuration.label
            } else {
                configuration.label
                    .padding(.horizontal, OMenuRowStyle.inset)
                    .frame(maxWidth: .infinity, minHeight: Theme.rowHeight, maxHeight: Theme.rowHeight, alignment: .leading)
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(fill))
        .contentShape(Rectangle())
        .onHover { hover.on = $0 }
    }
}
