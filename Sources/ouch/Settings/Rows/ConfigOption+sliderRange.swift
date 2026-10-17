import AppKit
import SwiftUI

extension ConfigOption {
    var ui: SettingInfo {
        guard let setting else { fatalError("config option \(key) has no Settings row") }
        return setting
    }

    var resetValue: Double { number(Config()) * ui.scale }

    func sliderRange(holding value: Double) -> ClosedRange<Double> {
        let r = ui.range ?? 0...1
        return min(r.lowerBound, value)...max(r.upperBound, value)
    }
}
