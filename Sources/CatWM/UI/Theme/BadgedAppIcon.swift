import AppKit
import CatWMKit
import CoreText
import SwiftUI

struct BadgedAppIcon: View {
    let badge: String
    let color: Color
    var size: CGFloat = 48

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: badge)
                    .font(Theme.symbol(size * 0.36, .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.surface, color)
                    .background(Circle().fill(Theme.surface).padding(-1.5))
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: size * 0.06, y: size * 0.04)
            }
            .animation(Motion.fadeMedium, value: badge)
            .accessibilityHidden(true)
    }
}
