import AppKit
import CatWMKit
import SwiftUI

extension SortModel {
    typealias Run = (@escaping () -> Void) -> Void

    private func workspaceMenu(current lead: CGWindowID, run: @escaping Run,
                               move: @escaping (Int) -> Void) -> MenuItem {
        let home = plan.lane(of: lead)
        return MenuItem(id: "workspace", kind: .sub, label: "Move to workspace",
                        children: plan.lanes.enumerated().map { index, lane in
                            MenuItem(id: "lane-\(lane.id)", kind: .radio,
                                     label: "\(lane.number) \(lane.name)".trimmingCharacters(in: .whitespaces),
                                     checked: home == index, action: { run { move(index) } })
                        })
    }

    private func bringBack(_ id: CGWindowID) -> MenuItem {
        MenuItem(id: "restore", label: "Bring back", action: { [weak self] in self?.restore(id) })
    }

    func windowMenu(_ item: SortItem, closing: Bool, tabbed: Bool, run: @escaping Run) -> [MenuItem] {
        let id = item.id
        if closing { return [bringBack(id)] }
        var items: [MenuItem] = []
        if tabbed {
            items.append(MenuItem(id: "untab", label: "Move out of group", action: { [weak self] in
                guard let self, let lane = plan.lane(of: id) else { return }
                run { self.place(id, inLane: lane) }
            }))
        }
        items.append(workspaceMenu(current: id, run: run) { [weak self] in self?.place(id, inLane: $0) })
        let placed = unplacedFullscreen(id) == nil
        let others = displays.filter { $0.id != current }
        if !tabbed, placed, !others.isEmpty {
            items.append(MenuItem(id: "display", kind: .sub, label: "Move to display",
                                  children: others.map { display in
                                      MenuItem(id: "display-\(display.id)", label: display.name,
                                               action: { [weak self] in run { self?.moveToDisplay(id, display.id) } })
                                  }))
        }
        if placed {
            items.append(.sep("close-sep"))
            items.append(MenuItem(id: "close", label: "Close window", danger: true,
                                  action: { [weak self] in run { self?.markClosing(id) } }))
        }
        return items
    }

    func tabGroupMenu(lead: CGWindowID, closing: Bool, run: @escaping Run) -> [MenuItem] {
        if closing { return [bringBack(lead)] }
        return [
            workspaceMenu(current: lead, run: run) { [weak self] in self?.place(lead, inLane: $0, tabs: true) },
            .sep("close-sep"),
            MenuItem(id: "close", label: "Close tabs", danger: true, action: { [weak self] in
                guard let self else { return }
                run { self.plan.tabs(of: lead).filter { !self.plan.isClosing($0) }.forEach(self.markClosing) }
            })
        ]
    }

    func laneMenu(_ lane: SortLane, index: Int, rename: @escaping () -> Void, run: @escaping Run) -> [MenuItem] {
        var items = [
            MenuItem(id: "rename", label: "Rename", action: rename),
            MenuItem(id: "layout", kind: .sub, label: "Layout", children: layouts.map { layout in
                MenuItem(id: "layout-\(layout.rawValue)", kind: .radio, label: layout == .bsp ? "BSP" : layout.title,
                         checked: lane.layout == layout,
                         action: { [weak self] in run { self?.setLayout(layout, of: index) } })
            })
        ]
        if plan.lanes.count > 1 {
            items.append(.sep("close-sep"))
            items.append(MenuItem(id: "close", label: "Close workspace", danger: true,
                                  action: { [weak self] in run { self?.closeLane(lane.id) } }))
        }
        return items
    }
}
