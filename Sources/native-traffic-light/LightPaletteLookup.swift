extension LightArt {
    static func normal(_ light: TrafficLights.Light, dark: Bool) -> LightArt {
        switch (light, dark) {
        case (.close, false): return lightClose
        case (.minimize, false): return lightMin
        case (.zoom, false): return lightZoom
        case (.close, true): return darkClose
        case (.minimize, true): return darkMin
        case (.zoom, true): return darkZoom
        }
    }

    static func pressed(_ light: TrafficLights.Light, dark: Bool) -> LightArt {
        switch (light, dark) {
        case (.close, false): return lightClosePressed
        case (.minimize, false): return lightMinPressed
        case (.zoom, false): return lightZoomPressed
        case (.close, true): return darkClosePressed
        case (.minimize, true): return darkMinPressed
        case (.zoom, true): return darkZoomPressed
        }
    }

    static func grey(dark: Bool) -> LightArt { dark ? darkGrey : lightGrey }
}
