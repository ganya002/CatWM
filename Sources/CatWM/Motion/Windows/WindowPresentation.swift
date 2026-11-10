import AppKit

protocol WindowPresentation: AnyObject {
    func prepare(_ moves: [Animator.Move], spec: MotionSpec)
    func follow(_ moves: [Animator.Move])
    func sizing(for move: Animator.Move, from: CGRect, spec: MotionSpec) -> ColorFillSizing?
    func update(_ frames: [CGWindowID: CGRect])
    func cancel(_ id: CGWindowID)
    func close()
}

extension WindowPresentation {
    func follow(_ moves: [Animator.Move]) { prepare(moves, spec: .instant) }
    func sizing(for _: Animator.Move, from _: CGRect, spec _: MotionSpec) -> ColorFillSizing? { nil }
}
