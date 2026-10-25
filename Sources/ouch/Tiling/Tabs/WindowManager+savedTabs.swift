import CoreGraphics
import Foundation

extension WindowManager {
    private static let legacyTabsKey = "tabs.groups"

    func loadTabs() {
        let defaults = UserDefaults.standard
        savedTabs = (defaults.stringArray(forKey: Self.legacyTabsKey) ?? []).compactMap(SavedTabs.init)
        defaults.removeObject(forKey: Self.legacyTabsKey)
        savedTabsUntil = Date().addingTimeInterval(SavedTabs.wait)
    }

    func restoreTabs() {
        guard !savedTabs.isEmpty else { return }
        let late = Date() >= savedTabsUntil
        savedTabs.removeAll { saved in
            let back = saved.members.filter { member in
                windows[member.id].map { window in
                    window.pid == member.pid && (member.bundleID == nil || window.bundleID == member.bundleID)
                        && !window.isFloating
                } == true
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
            windows[member].map { SavedTabs.Member(id: member, pid: $0.pid, bundleID: $0.bundleID) }
        }
        var saved = SavedTabs(members: members, active: group.active)
        saved.workspace = workspace
        savedTabs.append(saved)
        savedTabsUntil = Date().addingTimeInterval(SavedTabs.wait)
        for member in group.members where member != id { move(member, false) }
        move(id, true)
    }
}
