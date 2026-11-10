import AppKit
import CatWMKit
import SwiftUI

struct OStatus: View {
    enum Kind { case success, warning, danger, info }
    let kind: Kind
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(Theme.symbol(Theme.Icon.small, .semibold))
            Text(text).font(Theme.body(12.5, .medium)).oneLine()
        }
        .foregroundStyle(color)
    }

    private var symbol: String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }
    private var color: Color {
        switch kind {
        case .success: Theme.success
        case .warning: Theme.warning
        case .danger: Theme.danger
        case .info: Theme.accentInk
        }
    }
}

#if DEBUG
extension GalleryExamples {
    static let status = GalleryExample(order: 13) { AnyView(GalleryContent(model: $0).status) }
}

extension GalleryContent {
    @ViewBuilder var status: some View {
        block("Status") {
            HStack(spacing: Theme.Space.extraLarge) {
                OStatus(kind: .success, text: "Granted")
                OStatus(kind: .warning, text: "Safari won't shrink further")
                OStatus(kind: .danger, text: "Failed")
                OStatus(kind: .info, text: "Applies to new windows")
            }
        }
    }
}
#endif
