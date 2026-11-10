import AppKit
import CatWMKit
import SwiftUI

final class SortModel: ObservableObject {
    @Published var displays: [SortDisplay] = []
    @Published var current = ""
    @Published var plans: [String: SortPlan] = [:] {
        didSet {
            for (key, var displayPlan) in plans where displayPlan.perDisplay {
                displayPlan.followDesktopOrder()
                if displayPlan.lanes.map(\.workspace) != plans[key]?.lanes.map(\.workspace) { plans[key] = displayPlan }
            }
        }
    }
    @Published var hover: CGWindowID?
    @Published var selected: CGWindowID?
    @Published var notice: SortNotice?
    @Published var nextLayout: Layout = .tall
    @Published var drag: SortDrag?
    @Published var columnDrag: SortColumnDrag?
    @Published var over: SortZone?
    @Published var columnSlot: Int?
    @Published var reveal = SortReveal()
    @Published var focusName: UUID?
    @Published var moreToRight = false
    @Published var shown = false
    @Published var ghostShift = CGSize.zero
    var motion = PanelMotion.current

    var layouts: [Layout] = [.tall]
    var maxRows = 7
    var zones: [SortZone: CGRect] = [:]
    var finish: (String?) -> Void = { _ in }
    var openFullscreen: (CGWindowID) -> Void = { _ in }
    var revert: () -> Void = {}
    var changed: () -> Void = {}
    weak var scroller: NSScrollView?
    var binds: [UInt64: KeyBinding] = [:]
    var edgeTimer: Timer?
    var scrollObserver: Any?
    var running = false

    var plan: SortPlan {
        plans[current] ?? SortPlan(display: current, items: [:], lanes: [],
                                   existing: [], taken: [], active: nil)
    }

    var currentDisplay: SortDisplay? { displays.first { $0.id == current } }
    var nextName: String? { plan.canAdd(avoiding: reserved()) ? plan.available(avoiding: reserved()).first : nil }

    static let digits: [UInt16: Int] = Dictionary(uniqueKeysWithValues: (0...9).compactMap { digit in
        keyCodes["\(digit)"].map { ($0, digit == 0 ? 10 : digit) }
    })
}

struct SortColumnDrag {
    let lane: SortLane
    let ratio: CGFloat
    let mainCount: Int
    var location: CGPoint
    let grab: CGSize
}

struct SortDrag {
    let item: SortItem
    let closing: Bool
    var location: CGPoint
    let grab: CGSize
    var group: [SortItem] = []
    var id: CGWindowID { item.id }

    func carries(_ other: CGWindowID) -> Bool { other == id || group.contains { $0.id == other } }
}

struct SortNotice {
    var text: String
}

struct SortResult {
    let changed: Bool
    let closing: [CGWindowID]
}

struct SortReveal: Equatable {
    var id: CGWindowID = 0
    var lane: UUID?
    var token = 0
}

enum SortZone: Hashable {
    case lane(UUID), add, close, panel, display(String), row(CGWindowID), tabs(CGWindowID), scroller
}
