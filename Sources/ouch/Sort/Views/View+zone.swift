import AppKit
import SwiftUI

extension View {
    func zone(_ z: SortZone) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: SortZoneKey.self, value: [z: g.frame(in: .named("sort"))])
        })
    }

    func keepInside(_ origin: CGPoint) -> some View { KeepInside(origin: origin) { self } }
}
