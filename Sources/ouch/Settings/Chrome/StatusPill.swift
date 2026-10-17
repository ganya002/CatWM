import AppKit
import SwiftUI

struct StatusPill: View {
    @ObservedObject var doc: ConfigDocument
    @StateObject private var model = Model()

    final class Model: ObservableObject {
        @Published var saved = false
        private var hide: DispatchWorkItem?

        func flash() {
            withAnimation(Motion.easeOut) { saved = true }
            hide?.cancel()
            let work = DispatchWorkItem { [weak self] in withAnimation(Motion.fadeSlow) { self?.saved = false } }
            hide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
        }
    }

    private enum Message: Equatable { case error(String), problems(Int), skipped(Int), saved }

    private var message: Message? {
        if let err = doc.saveError { return .error(err) }
        if doc.problemCount > 0 { return .problems(doc.problemCount) }
        if model.saved { return .saved }
        if !doc.fileErrors.isEmpty { return .skipped(doc.fileErrors.count) }
        return nil
    }

    var body: some View {
        let message = message, undo = doc.hasChangesSinceOpen
        Group {
            if message != nil || undo {
                HStack(spacing: 10) {
                    if let message { label(message).transition(.opacity) }
                    if message != nil && undo { Rectangle().fill(Theme.hairline).frame(width: 1, height: 16) }
                    if undo {
                        OButton("Undo All Changes", icon: "arrow.uturn.backward", size: .sm) { doc.undoAllChanges() }
                        .tooltip("Go back to how things were when you opened Settings")
                    }
                }
                .padding(.leading, message == nil ? 5 : 14).padding(.trailing, undo ? 5 : 14)
                .frame(height: 36)
                .floatingGlass(Capsule())
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.easeOut, value: message)
        .animation(Motion.easeOut, value: undo)
        .onChange(of: doc.isDirty) { was, now in
            if was && !now && doc.saveError == nil { model.flash() }
        }
    }

    @ViewBuilder private func label(_ m: Message) -> some View {
        switch m {
        case .error(let err):
            OStatus(kind: .danger, text: "Couldn't save: \(err)").tooltip(err)
        case .problems(let n):
            OStatus(kind: .warning, text: "Fix \(n) shortcut\(n == 1 ? "" : "s") to save")
        case .skipped(let n):
            OStatus(kind: .warning, text: "\(n) line\(n == 1 ? "" : "s") in the config file skipped")
                .tooltip(doc.fileErrors.joined(separator: "\n"))
        case .saved:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(Theme.symbol(Theme.Icon.sm, .semibold))
                    .foregroundStyle(Theme.success)
                Text("Saved").font(Theme.body(12.5, .medium)).foregroundStyle(Theme.inkMuted)
            }
        }
    }
}
