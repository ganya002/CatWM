import AppKit
import CatWMKit
import SwiftUI

enum CatFeeling: String, CaseIterable {
    case content, alert, sad, annoyed, sleepy, shut

    var pose: CatPose {
        switch self {
        case .content:
            CatPose(left: CatEye(x: 256, y: 173, tilt: -11, chord: 42, rise: 9, width: 13),
                    right: CatEye(x: 348, y: 191, tilt: 19, chord: 40, rise: 9, width: 13))
        case .alert:
            CatPose(left: CatEye(x: 258, y: 168, tilt: 0, chord: 0, rise: 0, width: 24),
                    right: CatEye(x: 352, y: 186, tilt: 0, chord: 0, rise: 0, width: 24))
        case .sad:
            CatPose(left: CatEye(x: 256, y: 178, tilt: -24, chord: 40, rise: -8, width: 13),
                    right: CatEye(x: 348, y: 196, tilt: 28, chord: 38, rise: -8, width: 13))
        case .annoyed:
            CatPose(left: CatEye(x: 256, y: 176, tilt: 24, chord: 40, rise: 0, width: 13),
                    right: CatEye(x: 350, y: 190, tilt: -6, chord: 40, rise: 0, width: 13))
        case .sleepy:
            CatPose(left: CatEye(x: 256, y: 184, tilt: -4, chord: 40, rise: 4, width: 13),
                    right: CatEye(x: 348, y: 198, tilt: 10, chord: 38, rise: 4, width: 13))
        case .shut:
            CatPose(left: CatEye(x: 256, y: 186, tilt: -4, chord: 38, rise: 0, width: 13),
                    right: CatEye(x: 348, y: 199, tilt: 10, chord: 36, rise: 0, width: 13))
        }
    }

    var spring: Spring {
        switch self {
        case .alert: Spring(response: 0.31, dampingRatio: 0.63)
        case .sleepy, .shut: Spring(response: 0.94, dampingRatio: 1)
        case .content, .sad, .annoyed: Spring(response: 0.48, dampingRatio: 1)
        }
    }

    var blinkSpeed: Double? {
        switch self {
        case .shut: nil
        case .sleepy: 2.5
        case .content, .alert, .sad, .annoyed: 1
        }
    }
}

struct CatSymbol: View {
    var feeling = CatFeeling.content
    var lid = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CatShape(pose: feeling.pose, lid: lid)
            .fill(.foreground)
            .aspectRatio(CatShape.aspectRatio, contentMode: .fit)
            .animation(Motion.feeling(feeling.spring, reduce: reduceMotion), value: feeling)
            .accessibilityHidden(true)
    }

    static func image(_ feeling: CatFeeling = .content, height: CGFloat) -> NSImage {
        let size = CGSize(width: (height * CatShape.aspectRatio).rounded(.up), height: height)
        let path = CatShape(pose: feeling.pose).path(in: CGRect(origin: .zero, size: size)).cgPath
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "CatWM"
        return image
    }
}

#if DEBUG
extension GalleryExamples {
    static let cat = GalleryExample(order: 17) { AnyView(GalleryContent(model: $0).cat) }
}

extension GalleryContent {
    @ViewBuilder var cat: some View {
        block("Cat") {
            HStack(alignment: .bottom, spacing: Theme.Space.extraLarge) {
                ForEach(CatFeeling.allCases, id: \.self) { feeling in
                    VStack(spacing: Theme.Space.extraSmall) {
                        CatSymbol(feeling: feeling).frame(height: 40)
                        Text(feeling.rawValue).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                    }
                }
                Image(nsImage: CatSymbol.image(height: 16))
            }
            .foregroundStyle(Theme.ink)
        }
    }
}
#endif
