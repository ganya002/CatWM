import AppKit
import SwiftUI

struct GuideView: View {
    @ObservedObject var model: GuideModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.granted {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(Theme.symbol(Theme.Icon.xl, .regular)).foregroundStyle(Theme.success)
                        .transition(.symbolEffect(.appear))
                    Text("All set").textStyle(.title).oneLine()
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open").font(Theme.symbol()).foregroundStyle(Theme.accentInk)
                        Text(model.kind.title).kicker()
                    }
                    Text("Allow Ouch").textStyle(.title).oneLine().padding(.top, 6)
                    Text(model.alertUp ? "macOS asks first, then System Settings opens." : "Follow these steps in System Settings.")
                        .font(Theme.body(13)).foregroundStyle(Theme.inkMuted).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 10) {
                    if model.alertUp {
                        OStep(n: 1, text: "In the macOS alert, click **Open System Settings**.")
                        OStep(n: 2, text: "Turn its switch **on**. Enter your password if asked.")
                    } else {
                        OStep(n: 1, text: "Find **Ouch** in the \(model.kind.title) list.")
                        OStep(n: 2, text: "Turn its switch **on**. Enter your password if asked.")
                        OStep(n: 3, text: "Not in the list? Click **+**, or drag this icon into it:")
                    }
                }
                if !model.alertUp { dragTile }

                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                    Text("Waiting…").textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                    Spacer(minLength: 4)
                    OButton("Reset", variant: .ghost, size: .sm) {
                        model.kind.reset()
                    }
                    .tooltip("Clears a stale entry left by a rebuilt or moved copy of the app")
                    OButton("Hide", size: .sm, action: dismiss)
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        .foregroundStyle(Theme.ink)
        .ignoresSafeArea()
        .animation(Motion.easeOut, value: model.granted)
        .animation(Motion.easeOut, value: model.alertUp)
    }

    private var dragTile: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
            Text("Ouch").font(Theme.body(14, .medium))
            Spacer()
            Image(systemName: "hand.draw").foregroundStyle(Theme.inkMuted)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(Theme.well))
        .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
        .tooltip("Drag into the \(model.kind.title) list")
    }
}
