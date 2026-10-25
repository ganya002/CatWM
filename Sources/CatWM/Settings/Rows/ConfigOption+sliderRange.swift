import AppKit
import SwiftUI

extension ConfigOption {
    var settingInfo: SettingInfo {
        guard let setting else { fatalError("config option \(key) has no Settings row") }
        return setting
    }

    var resetValue: Double { number(Config()) * settingInfo.scale }

    func sliderRange(holding value: Double) -> ClosedRange<Double> {
        let range = settingInfo.range ?? 0...1
        return min(range.lowerBound, value)...max(range.upperBound, value)
    }
}
