import AppKit
import CatWMKit
import SwiftUI

struct FinishCardView: View {
    @ObservedObject var model: CoachModel
    let summary: Coach.Summary
    static let width: CGFloat = 540
    private static let pad = EdgeInsets(top: 26, leading: 28, bottom: 0, trailing: 28)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Density.extraLarge.radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            title
            if !model.text.isEmpty {
                Text(model.text).font(Theme.body()).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            if !summary.modeCaps.isEmpty { mode.padding(.top, Theme.Space.medium) }
            columns.padding(.top, 16)
            footer.padding(.top, Theme.Space.extraLarge).padding(.bottom, 21)
        }
        .padding(Self.pad)
        .frame(width: Self.width, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.accent).frame(height: 3) }
        .clipShape(shape)
        .foregroundStyle(Theme.ink)
        .background(shape.fill(Theme.surfaceRaised).elevation(.float, in: shape))
    }

    private var title: Text {
        let parts = model.title.split(separator: "*", omittingEmptySubsequences: false)
        return parts.enumerated().reduce(Text("")) { text, part in
            text + Text(part.element).foregroundColor(part.offset.isMultiple(of: 2) ? Theme.inkMuted : Theme.ink)
        }
        .font(Theme.display(30)).tracking(-0.6)
    }

    private var mode: some View {
        HStack(spacing: Theme.Space.medium) {
            Kbd(keys: summary.modeCaps, size: .medium).fixedSize()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.modeName).font(Theme.body(13.5, .medium)).oneLine().fixedSize()
                (Text("Press it first. ") + Text("Esc").font(Theme.keys(12, .medium)) + Text(" or a click leaves it."))
                    .textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var columns: some View {
        let count = summary.groups.map(\.column).max() ?? 1
        return HStack(alignment: .top, spacing: Theme.Space.extraLarge) {
            ForEach(1...max(1, count), id: \.self) { col in
                VStack(alignment: .leading, spacing: Theme.Space.medium) {
                    let columnGroups = Array(summary.groups.enumerated()).filter { $0.element.column == col }
                    ForEach(columnGroups, id: \.offset) { _, summaryGroup in
                        group(summaryGroup)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func group(_ summaryGroup: Coach.SummaryGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OSectionHeader(summaryGroup.title, tone: Theme.inkMuted).padding(.bottom, Theme.Space.extraSmall)
            ForEach(Array(summaryGroup.rows.enumerated()), id: \.offset) { i, row in
                HStack(spacing: Theme.Space.medium) {
                    Text(row.label).font(Theme.body()).oneLine()
                    Spacer(minLength: 8)
                    Kbd(keys: row.caps).fixedSize()
                }
                .frame(minHeight: 30)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) } }
            }
        }
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                hint
                Spacer(minLength: 8)
                buttons
            }
            VStack(alignment: .trailing, spacing: 12) {
                hint.frame(maxWidth: .infinity, alignment: .leading)
                buttons
            }
        }
    }

    @ViewBuilder private var hint: some View {
        if let key = summary.helpKey {
            HStack(spacing: 4) {
                Kbd(keys: [key])
                Text("in \(summary.modeName.lowercased()) shows every key on the keyboard")
                    .textStyle(.caption).foregroundStyle(Theme.inkFaint).oneLine()
            }
            .fixedSize()
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if summary.tutorial { OButton("Start the tutorial", variant: .ghost, action: model.tutorial) }
            OButton(model.button ?? "Finish", variant: .primary, shortcut: ["↩"], action: model.next)
                .keyboardShortcut(.defaultAction)
        }
        .fixedSize()
    }
}
