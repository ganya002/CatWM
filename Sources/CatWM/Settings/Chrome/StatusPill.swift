import AppKit
import CatWMKit
import SwiftUI

struct StatusPill: View {
    @ObservedObject var doc: ConfigDocument

    private enum Message: Equatable { case error(String), problems(Int), skipped(Int) }

    private var message: Message? {
        if let err = doc.saveError { return .error(err) }
        if doc.problemCount > 0 { return .problems(doc.problemCount) }
        if !doc.fileErrors.isEmpty { return .skipped(doc.fileErrors.count) }
        return nil
    }

    var body: some View {
        let message = message
        Group {
            if let message {
                label(message)
                    .padding(.horizontal, Theme.Space.medium)
                    .frame(height: 36)
                    .floatingGlass(Capsule())
                    .padding(.bottom, Theme.Space.medium)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.easeOut, value: message)
    }

    @ViewBuilder private func label(_ message: Message) -> some View {
        switch message {
        case .error(let err):
            OStatus(kind: .danger, text: "Couldn't save: \(err)")
        case .problems(let count):
            OStatus(kind: .warning, text: "Fix \(count) shortcut\(count == 1 ? "" : "s") to save")
        case .skipped(let count):
            OStatus(kind: .warning, text: "\(count) line\(count == 1 ? "" : "s") in the config file skipped")
                .tooltip(doc.fileErrors.joined(separator: "\n"))
        }
    }
}
