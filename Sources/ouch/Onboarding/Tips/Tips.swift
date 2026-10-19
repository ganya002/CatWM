import AppKit
import SwiftUI

final class Tips: ObservableObject {
    static let shared = Tips()

    enum TipPlace: Equatable { case settings(String), menuBar, modeBar }

    struct Tip: Equatable {
        let id: String
        let title: String
        var body: String?
        var chords: [[String]] = []
        let place: TipPlace
        var action: (label: String, run: () -> Void)?

        static func == (lhs: Tip, rhs: Tip) -> Bool { lhs.id == rhs.id }
    }

    enum Known: String { case tutorial, keyHelp }

    @Published var settings: Tip?
    var global: Tip?
    var panel: OuchPanel?
    var hideWork: DispatchWorkItem?
    var pendingWork: DispatchWorkItem?
    var modeEntries = 0

    static let minDaysUsed = 7
    static let cooldown: TimeInterval = 5 * 24 * 3600
    static let paneOpens = 5, menuClicks = 8, modeEntriesNeeded = 15
    static let paneDelay: TimeInterval = 8

    let defaults = UserDefaults.standard
    static let seenKey = "tips.seen", offKey = "tips.off", clicksKey = "tips.clicks"
    static let daysKey = "tips.days", lastKey = "tips.last", panesKey = "tips.panes"

    var enabled: Bool {
        get { !defaults.bool(forKey: Self.offKey) }
        set {
            defaults.set(!newValue, forKey: Self.offKey)
            if newValue {
                for key in [Self.seenKey, Self.clicksKey, Self.panesKey, Self.lastKey] {
                    defaults.removeObject(forKey: key)
                }
            } else {
                dismissAll()
            }
        }
    }

    var seen: Set<String> { Set(defaults.stringArray(forKey: Self.seenKey) ?? []) }

    var daysUsed: Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var days = Set(defaults.stringArray(forKey: Self.daysKey) ?? [])
        if days.insert(formatter.string(from: Date())).inserted { defaults.set(Array(days), forKey: Self.daysKey) }
        return days.count
    }

    var rested: Bool {
        Date().timeIntervalSince1970 - defaults.double(forKey: Self.lastKey) >= Self.cooldown
    }
}
