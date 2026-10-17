import AppKit
import SwiftUI

struct OMenuRow<Lead: View, Label: View, Trailing: View>: View {
    var highlighted: Bool? = nil
    var open = false
    var danger = false
    let action: () -> Void
    @ViewBuilder var lead: Lead
    @ViewBuilder var label: Label
    @ViewBuilder var trailing: Trailing

    init(highlighted: Bool? = nil, open: Bool = false, danger: Bool = false, action: @escaping () -> Void,
         @ViewBuilder lead: () -> Lead, @ViewBuilder label: () -> Label, @ViewBuilder trailing: () -> Trailing) {
        self.highlighted = highlighted; self.open = open; self.danger = danger; self.action = action
        self.lead = lead(); self.label = label(); self.trailing = trailing()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if Lead.self != EmptyView.self { lead.frame(width: 16) }
                label
                Spacer(minLength: 6)
                trailing
            }
            .font(Theme.body(13.5))
            .foregroundStyle(danger ? Theme.danger : Theme.ink)
        }
        .buttonStyle(OMenuRowStyle(highlighted: highlighted, open: open, danger: danger))
    }
}
