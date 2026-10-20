import AppKit

extension Steps {
    static func quickActions(_ coach: Coach) -> [PlannedStep] {
        let mods = coach.windowManager.config.mainMod.union(coach.book.enter?.mods ?? [])
        guard coach.windowManager.config.cursorActions, !coach.book.mode.isEmpty,
              let tap = KeyWords.modLabels(mods, long: true).first else { return [] }
        let open = PlannedStep { _ in
            Step(title: "Quick actions at the pointer",
                 text: "In window mode, tap \(tap) by itself. A menu opens at the pointer.",
                 target: .mode, caps: [tap], needsMode: true,
                 accept: { event in
                     if case .tick = event, CursorActions.shared.isMenuOpen { return "" }
                     return nil
                 }, simulate: { CursorActions.shared.tapped() })
        }
        let close = PlannedStep { _ in
            Step(title: "Templates and dim live here",
                 text: "Save this workspace, open a saved one, or dim the other windows. Esc closes it.",
                 target: .mode, caps: ["esc"],
                 accept: { event in
                     if case .tick = event, !CursorActions.shared.isMenuOpen { return "" }
                     return nil
                 }, simulate: { CursorActions.shared.dismissMenu() })
        }
        return [open, close]
    }
}
