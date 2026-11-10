import CatWMKit
import SwiftUI

enum CatMove: CaseIterable {
    case hop, spin, wiggle, look
}

struct CatMoves: Equatable {
    private(set) var move = CatMove.hop
    private(set) var count = 0

    mutating func play(_ move: CatMove) {
        self.move = move
        count += 1
    }
}

struct CatMascot: View {
    var feeling: CatFeeling
    var moves: CatMoves
    var look: CGVector?
    @State private var puppet: CatPuppet
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(feeling: CatFeeling = .content, moves: CatMoves = CatMoves(), look: CGVector? = nil) {
        self.feeling = feeling
        self.moves = moves
        self.look = look
        _puppet = State(initialValue: CatPuppet(feeling: feeling, at: Date.now.timeIntervalSinceReferenceDate))
    }

    var body: some View {
        Group {
            if reduceMotion {
                CatSymbol(feeling: feeling)
            } else {
                TimelineView(.animation) { context in
                    CatFrameView(frame: puppet.frame(at: context.date.timeIntervalSinceReferenceDate))
                }
            }
        }
        .aspectRatio(CatShape.aspectRatio, contentMode: .fit)
        .onChange(of: feeling) { _, next in puppet.show(next, at: Date.now.timeIntervalSinceReferenceDate) }
        .onChange(of: moves) { _, next in puppet.play(next.move, at: Date.now.timeIntervalSinceReferenceDate) }
        .onChange(of: look) { _, next in puppet.gaze = next }
        .accessibilityHidden(true)
    }
}

struct CatFrameView: View {
    let frame: CatFrame

    var body: some View {
        GeometryReader { geometry in
            let motion = frame.motion, width = 1 + (1 - motion.stretch) * 0.7
            CatShape(pose: frame.pose, lid: frame.lid, look: CGVector(dx: motion.lookX, dy: motion.lookY))
                .fill(.foreground)
                .scaleEffect(x: width, y: motion.stretch, anchor: .bottom)
                .rotationEffect(.degrees(motion.lean), anchor: .bottom)
                .offset(y: -motion.lift * geometry.size.height)
        }
    }
}

#if DEBUG
extension GalleryExamples {
    static let catMascot = GalleryExample(order: 18) { AnyView(GalleryContent(model: $0).catMascot) }
}

extension GalleryContent {
    @ViewBuilder var catMascot: some View {
        block("Cat mascot") {
            HStack(alignment: .center, spacing: Theme.Space.extraLarge) {
                CatMascot(feeling: model.catFeeling, moves: model.catMoves).frame(height: 120)
                    .foregroundStyle(Theme.ink)
                    .padding(.top, Theme.Space.xxl)
                OButton("Hop") { model.catMoves.play(.hop) }
                OButton("Spin") { model.catMoves.play(.spin) }
                OButton("Wiggle") { model.catMoves.play(.wiggle) }
                OButton("Look") { model.catMoves.play(.look) }
                OButton("Next feeling", variant: .ghost) {
                    let all = CatFeeling.allCases
                    model.catFeeling = all[((all.firstIndex(of: model.catFeeling) ?? 0) + 1) % all.count]
                }
            }
        }
    }
}
#endif
