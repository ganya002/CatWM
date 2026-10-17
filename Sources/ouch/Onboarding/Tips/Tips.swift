import AppKit
import SwiftUI

final class Tips: ObservableObject {

    static let shared = Tips()

    struct Tip: Equatable {
        enum Place: Equatable { case settings(String), menuBar, modeBar }
        let id: String
        let title: String
        var body: String?
        var chords: [[String]] = []
        let place: Place
        var action: (label: String, run: () -> Void)?

        static func == (a: Tip, b: Tip) -> Bool { a.id == b.id }
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
                for k in [Self.seenKey, Self.clicksKey, Self.panesKey, Self.lastKey] { defaults.removeObject(forKey: k) }
            } else {
                dismissAll()
            }
        }
    }

    var seen: Set<String> { Set(defaults.stringArray(forKey: Self.seenKey) ?? []) }

    var daysUsed: Int {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        var days = Set(defaults.stringArray(forKey: Self.daysKey) ?? [])
        if days.insert(f.string(from: Date())).inserted { defaults.set(Array(days), forKey: Self.daysKey) }
        return days.count
    }

    var rested: Bool {
        Date().timeIntervalSince1970 - defaults.double(forKey: Self.lastKey) >= Self.cooldown
    }

}
