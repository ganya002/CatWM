import AppKit

extension Steps {
    static func sendGlobal(_ coach: Coach) -> PlannedStep? {
        guard let sendTo = coach.sendTo,
              let send = coach.book.find(["movetoworkspace"], sendTo, global: true) else { return nil }
        return PlannedStep { coach in
            Step(title: "Move a window to a workspace",
                 text: "Hold the keys from anywhere. The window goes with you.",
                 target: .window, caps: KeyWords.caps(send, long: true),
                 accept: { event in
                     if case .command("movetoworkspace", _, _) = event { return "" }
                     return nil
                 }, simulate: {
                     Hotkeys.shared.setSubmap("")
                     coach.windowManager.dispatch("movetoworkspace", sendTo)
                 })
        }
    }
}
