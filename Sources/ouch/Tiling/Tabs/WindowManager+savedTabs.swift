import CoreGraphics
import Foundation

extension WindowManager {
    private static let savedTabsKey = "tabs.groups"
    private static let savedTabsWait: TimeInterval = 10

    func loadTabs() {
        savedTabs = (UserDefaults.standard.stringArray(forKey: Self.savedTabsKey) ?? []).compactMap(SavedTabs.init)
        savedTabsUntil = Date().addingTimeInterval(Self.savedTabsWait)
    }

    func restoreTabs() {
        guard !savedTabs.isEmpty else { return }
        let late = Date() >= savedTabsUntil
        savedTabs.removeAll { saved in
            let back = saved.members.filter { member in
                windows[member.id].map { $0.pid == member.pid && !$0.isFloating } == true
            }.map(\.id)
            let workspace = saved.workspace ?? back.first.flatMap { workspaceOf[$0] }
            let ready = back.filter { workspace != nil && workspaceOf[$0] == workspace }
            guard ready.count == saved.members.count || late else { return false }
            guard ready.count > 1 else { return true }
            let focused = focusedWindow()?.id
            model.restoreTabs(ready, active: focused.flatMap { ready.contains($0) ? $0 : nil } ?? saved.active)
            Log.info("tabs: restored the tabs \(ready.map(String.init).joined(separator: " "))")
            return true
        }
    }

    func moveTabs(of id: CGWindowID, to workspace: String?, _ move: (_ member: CGWindowID, _ lead: Bool) -> Void) {
        guard let group = tabs.group(of: id), let workspace else { return move(id, true) }
        let members = group.members.compactMap { member in
            windows[member].map { SavedTabs.Member(id: member, pid: $0.pid) }
        }
        var saved = SavedTabs(members: members, active: group.active)
        saved.workspace = workspace
        savedTabs.append(saved)
        savedTabsUntil = Date().addingTimeInterval(Self.savedTabsWait)
        for member in group.members where member != id { move(member, false) }
        move(id, true)
    }

    func saveTabs() {
        guard savedTabs.isEmpty else { return }
        let lines = tabs.groups.map { group in
            SavedTabs(members: group.members.compactMap { id in windows[id].map { .init(id: id, pid: $0.pid) } },
                      active: group.active).line
        }
        guard lines != lastSavedTabs else { return }
        lastSavedTabs = lines
        UserDefaults.standard.set(lines, forKey: Self.savedTabsKey)
    }
}
