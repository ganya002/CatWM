extension LightArt {
    static func s(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double) -> ArtStop {
        ArtStop(red: red, green: green, blue: blue, alpha: alpha)
    }
}

extension GlyphKind {
    var shape: GlyphShape {
        switch self {
        case .close: GlyphShape(length: 9.475, width: 2.0, radius: 1.0, dx: 0, dy: 0)
        case .minimize: GlyphShape(length: 8.0, width: 2.0, radius: 1.0, dx: 0, dy: 0)
        case .zoomPlus: GlyphShape(length: 8.0, width: 2.0, radius: 1.0, dx: 0, dy: 0)
        case .zoomArrows: GlyphShape(length: 4.84, width: 0.6, radius: 2.97, dx: 0, dy: 0)
        }
    }

    func color(dark: Bool, pressed: Bool) -> ArtStop {
        let stop = LightArt.s
        switch (self, dark, pressed) {
        case (.close, false, false):
            return stop(0.640, 0.000, 0.000, 1.000)
        case (.close, false, true):
            return stop(0.862, 0.000, 0.000, 0.992)
        case (.close, true, false):
            return stop(0.547, 0.000, 0.000, 0.987)
        case (.close, true, true):
            return stop(0.738, 0.000, 0.000, 1.000)
        case (.minimize, false, false):
            return stop(0.743, 0.235, 0.000, 0.931)
        case (.minimize, false, true):
            return stop(1.000, 0.357, 0.000, 1.000)
        case (.minimize, true, false):
            return stop(0.613, 0.169, 0.000, 0.892)
        case (.minimize, true, true):
            return stop(0.824, 0.074, 0.000, 0.745)
        case (.zoomPlus, false, false):
            return stop(0.208, 0.528, 0.000, 0.982)
        case (.zoomPlus, false, true):
            return stop(0.281, 0.713, 0.000, 1.000)
        case (.zoomPlus, true, false):
            return stop(0.181, 0.449, 0.000, 0.996)
        case (.zoomPlus, true, true):
            return stop(0.248, 0.580, 0.000, 0.954)
        case (.zoomArrows, false, false):
            return stop(0.213, 0.533, 0.000, 0.996)
        case (.zoomArrows, false, true):
            return stop(0.281, 0.713, 0.000, 1.000)
        case (.zoomArrows, true, false):
            return stop(0.182, 0.448, 0.000, 0.978)
        case (.zoomArrows, true, true):
            return stop(0.248, 0.580, 0.000, 0.954)
        }
    }
}
