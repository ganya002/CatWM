#if DEBUG

import AppKit
import SwiftUI

struct ColorToken: Identifiable {
    let name: String
    let path: KeyPath<Palette, Palette.Pair>
    var id: String { name }

    static let all: [ColorToken] = [
        ColorToken(name: "bg", path: \.bg), ColorToken(name: "surface", path: \.surface),
        ColorToken(name: "surfaceRaised", path: \.surfaceRaised), ColorToken(name: "surfaceSunken", path: \.surfaceSunken),
        ColorToken(name: "hover", path: \.hover), ColorToken(name: "hairline", path: \.hairline),
        ColorToken(name: "borderControl", path: \.borderControl),
        ColorToken(name: "ink", path: \.ink), ColorToken(name: "inkMuted", path: \.inkMuted), ColorToken(name: "inkFaint", path: \.inkFaint),
        ColorToken(name: "accent", path: \.accent), ColorToken(name: "accentHover", path: \.accentHover),
        ColorToken(name: "onAccent", path: \.onAccent), ColorToken(name: "accentInk", path: \.accentInk),
        ColorToken(name: "accentSoft", path: \.accentSoft), ColorToken(name: "tint", path: \.tint), ColorToken(name: "focus", path: \.focus),
        ColorToken(name: "success", path: \.success), ColorToken(name: "warning", path: \.warning),
        ColorToken(name: "danger", path: \.danger), ColorToken(name: "dangerSoft", path: \.dangerSoft),
        ColorToken(name: "glass", path: \.glass), ColorToken(name: "wash1", path: \.wash1), ColorToken(name: "wash2", path: \.wash2),
    ]
}

#endif
