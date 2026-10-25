import AppKit

extension Steps {
    static func switcher(_ coach: Coach) -> PlannedStep? {
        guard let bind = coach.book.find(["switcher"], "", global: true) else { return nil }
        return PlannedStep { coach in
            Step(title: "Switch to any window",
                 text: "Tap it for your last window. Hold it to see every window, type to search, then release.",
                 caps: KeyWords.caps(bind, long: true),
                 accept: { event in
                     if case .command("switcher", _, _) = event { return "" }
                     return nil
                 }, simulate: {
                     Hotkeys.shared.setSubmap("")
                     DispatchQueue.main.async { coach.windowManager.dispatch("switcher", "") }
                 })
        }
    }
}
