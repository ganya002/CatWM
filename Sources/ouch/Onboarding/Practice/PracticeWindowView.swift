import AppKit
import SwiftUI

struct PracticeWindowView: View {
    let app: DemoApp
    @Environment(\.controlActiveState) private var active

    var body: some View {
        Text(app.title)
            .font(Theme.body(13, .medium))
            .foregroundStyle(app.dark ? Color.white.opacity(0.62) : Color.black.opacity(0.55))
            .lineLimit(1)
            .padding(.leading, 78)
            .frame(height: 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(app.color)
            .ignoresSafeArea()
            .overlay {
                if active == .key {
                    RoundedRectangle(cornerRadius: 11, style: .continuous) // style-ok: follows the macOS window corner
                        .strokeBorder(Theme.accent, lineWidth: 2.5)
                        .padding(2)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
    }
}
