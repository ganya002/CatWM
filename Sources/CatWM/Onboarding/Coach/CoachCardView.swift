import AppKit
import CatWMKit
import SwiftUI

struct CoachCardView: View {
    @ObservedObject var model: CoachModel
    static let width: CGFloat = 344
    static var inset: EdgeInsets { EdgeInsets(all: Elevation.float.room) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let summary = model.summary {
            FinishCardView(model: model, summary: summary).padding(Self.inset)
        } else {
            step
        }
    }

    private var step: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if model.canHead {
                    OIconButton(symbol: model.headSymbol ?? "xmark", label: model.headLabel, action: model.headAction)
                        .padding(.leading, -6)
                }
                Image(systemName: model.recall ? "brain" : "keyboard")
                    .font(Theme.symbol())
                    .contentTransition(.symbolEffect(.replace))
                Spacer(minLength: 0)
            }
            .frame(minHeight: 22)
            Text(model.title).textStyle(.title).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12).padding(.bottom, 4)
            if !model.text.isEmpty {
                Text(model.text).font(Theme.body()).lineSpacing(2).opacity(0.86)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.caps.isEmpty { keys.padding(.top, 16) }
            if let warning = model.warning {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                    Text(warning).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.well))
                .padding(.top, Theme.Space.medium)
            }
            if let button = model.button {
                HStack {
                    Spacer()
                    OButton(button, variant: .primary, shortcut: ["↩"], action: model.next)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 20)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceSunken)
                    Capsule().fill(Theme.accent).frame(width: geometry.size.width * model.progress)
                }
            }
            .frame(height: 3)
            .padding(.top, Theme.Space.medium)
            .animation(Motion.spring, value: model.progress)
        }
        .frame(width: Self.width - 40)
        .surface(.large, caret: caret)
        .padding(Self.inset)
        .animation(Motion.fadeMedium, value: model.done)
        .animation(Motion.fadeMedium, value: model.hidden)
    }

    private var keys: some View {
        HStack(spacing: 12) {
            if model.hidden {
                Kbd(keys: model.caps.map { _ in " " }, size: .large).opacity(0.5)
                    .accessibilityHidden(true)
                Button(action: model.reveal) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb").breatheEffect()
                        Text("Hint")
                    }
                }
                .buttonStyle(OButtonStyle(variant: .ghost, size: .small))
            } else {
                Button(action: model.tryKeys) { caps.fixedSize().contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Press the keys, or click them")
                if model.button == nil { status }
            }
        }
    }

    @ViewBuilder private var caps: some View {
        if model.capsDone.count == model.caps.count, !model.capsDone.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(model.caps.enumerated()), id: \.offset) { i, key in
                    Kbd(keys: [key], size: .large, pressed: model.capsDone[i])
                        .overlay(alignment: .topTrailing) {
                            if model.capsDone[i] {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(Theme.symbol(Theme.Icon.medium, .semibold))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Theme.onAccent, Theme.success)
                                    .background(Circle().fill(Theme.surfaceRaised).padding(-1.5))
                                    .offset(x: 6, y: -6)
                                    .transition(.symbolEffect(.appear))
                            }
                        }
                        .animation(Motion.spring, value: model.capsDone[i])
                }
            }
        } else {
            Kbd(keys: model.caps, size: .large, pressed: model.pressed)
        }
    }

    @ViewBuilder private var status: some View {
        if model.done {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                .transition(.symbolEffect(.appear))
                .accessibilityLabel("Done")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        } else {
            let icon = Image(systemName: "cursorarrow.rays").symbolEffect(.pulse, isActive: !reduceMotion)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    icon
                    Text("Press it now").font(Theme.body()).oneLine().fixedSize()
                }
                icon
            }
            .accessibilityLabel("Press it now")
            .opacity(0.8)
        }
    }

    private var caret: Caret {
        switch model.caret {
        case .none: .none
        case .pointingUp(let x): .top(x)
        case .down: .bottom
        }
    }
}
