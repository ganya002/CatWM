import AppKit
import SwiftUI

struct SortOfferView: View {
    let caret: CGFloat
    let choose: (Bool) -> Void
    static let width: CGFloat = 344
    static let inset = EdgeInsets(top: 32, leading: 52, bottom: 68, trailing: 52)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(Theme.symbol())
                Spacer(minLength: 8)
            }
            .frame(minHeight: 22)
            Text("Your workspace is crowded").textStyle(.title)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 12).padding(.bottom, 4)
            HStack(spacing: 4) {
                OButton("Sort my windows", variant: .primary, shortcut: ["↩"]) { choose(true) }
                    .keyboardShortcut(.defaultAction)
                OButton("Keep as is", variant: .ghost) { choose(false) }
            }
            .padding(.top, 20)
            Capsule().fill(Theme.accent).frame(height: 3).padding(.top, 14)
        }
        .frame(width: Self.width - 40)
        .surface(.lg, caret: .top(caret))
        .padding(Self.inset)
        .fixedSize()
    }
}
