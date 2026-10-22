import AppKit

enum SharedSpaces {
    static func isOn(displays count: Int) -> Bool { count > 1 && !NSScreen.screensHaveSeparateSpaces }

    static func display(of frame: CGRect, kept: String?, target: CGRect?, settling: Bool,
                        in screens: [(id: String, frame: CGRect)]) -> String? {
        let kept = kept.flatMap { id in screens.contains { $0.id == id } ? id : nil }
        if let kept, settling || target.map { frame.approxEqual($0) } == true { return kept }
        guard !frame.isNull else { return kept ?? screens.first?.id }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        if let hit = screens.first(where: { $0.frame.contains(centre) }) { return hit.id }
        func overlap(_ rect: CGRect) -> CGFloat {
            let shared = rect.intersection(frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        let best = screens.max { overlap($0.frame) < overlap($1.frame) }
        return best.map { overlap($0.frame) > 0 } == true ? best?.id : kept ?? screens.first?.id
    }
}
