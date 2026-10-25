import Foundation
import QuartzCore

struct TilingTiming {
    let name: String
    let windows: Int
    private let start = CACurrentMediaTime()

    init(_ name: String, windows: Int) {
        self.name = name
        self.windows = windows
    }

    func checkpoint(_ phase: String) {
        Log.debug(String(format: "tiling: %@ %@ +%.1fms", name, phase, (CACurrentMediaTime() - start) * 1000))
    }

    func finish() {
        let elapsed = (CACurrentMediaTime() - start) * 1000
        guard Log.verbose || elapsed > 1000.0 / 60.0 else { return }
        Log.info(String(format: "tiling: %@ windows %d %.1fms", name, windows, elapsed))
    }
}
