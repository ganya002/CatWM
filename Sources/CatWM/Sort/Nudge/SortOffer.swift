import AppKit
import CatWMKit
import SwiftUI

final class SortOffer {
    static let shared = SortOffer()
    private var panel: CatWMPanel?
    private var finish: ((Bool) -> Void)?
    private var timeout: DispatchWorkItem?

    func show(button: NSStatusBarButton?, on screen: NSScreen,
              done: @escaping (_ sort: Bool) -> Void) {
        finish = done
        let view = SortOfferView(caret: 0) { [weak self] in self?.end($0) }
        var host = CatWMHostingView(rootView: view)
        let size = host.fittingSize
        let visible = screen.visibleFrame
        var x = visible.midX - size.width / 2, y = visible.maxY - size.height - 16
        var caret: CGFloat = SortOfferView.width / 2
        if let buttonFrame = button?.window?.frame {
            let card = SortOfferView.width
            let inset = SortOfferView.inset
            let left = min(max(buttonFrame.midX - card + 60, visible.minX + 16), visible.maxX - card - 16)
            x = left - inset.leading
            y = buttonFrame.minY - 10 - (size.height - inset.top - inset.bottom) - inset.bottom
            caret = min(max(buttonFrame.midX - left, 20), card - 20)
        }
        host = CatWMHostingView(rootView: SortOfferView(caret: caret) { [weak self] in
            self?.end($0)
        })
        let card = CatWMPanel(role: .overlay(.floating, clickThrough: false),
                             frame: CatWMPanel.frame(size: size, on: screen, anchor: .origin(NSPoint(x: x, y: y)),
                                                    inset: SortOfferView.inset).integral)
        card.contentView = host
        card.alphaValue = 0
        card.orderFrontRegardless()
        Motion.group(0.35) { Motion.setAlpha(1, on: card) }
        panel = card
        let work = DispatchWorkItem { [weak self] in self?.end(false) }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    private func end(_ sort: Bool) {
        timeout?.cancel()
        timeout = nil
        guard let card = panel else { return }
        panel = nil
        let done = finish
        finish = nil
        Motion.group(0.25, changes: { Motion.setAlpha(0, on: card) }, completion: { card.orderOut(nil) })
        done?(sort)
    }
}

struct SortOfferView: View {
    let caret: CGFloat
    let choose: (Bool) -> Void
    static let width: CGFloat = 344
    static var inset: EdgeInsets { EdgeInsets(all: Elevation.float.room) }

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
                OButton("Open Overview", variant: .primary, shortcut: ["↩"]) { choose(true) }
                    .keyboardShortcut(.defaultAction)
                OButton("Keep as is", variant: .ghost) { choose(false) }
            }
            .padding(.top, 20)
            Capsule().fill(Theme.accent).frame(height: 3).padding(.top, Theme.Space.medium)
        }
        .frame(width: Self.width - 40)
        .surface(.large, caret: .top(caret))
        .padding(Self.inset)
        .fixedSize()
    }
}
