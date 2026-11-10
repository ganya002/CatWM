import CoreGraphics
import Foundation

package struct SavedTabs: Equatable {
    package struct Member: Equatable {
        package let id: CGWindowID
        package let pid: pid_t
        package var bundleID: String?

        package var identity: TilingRecovery.Identity { .init(id: id, pid: pid, bundleID: bundleID) }
    }

    package static let wait: TimeInterval = 10

    package var members: [Member]
    package let active: CGWindowID
    package var workspace: String?

    package init(members: [Member], active: CGWindowID) {
        self.members = members
        self.active = active
    }

    package init?(_ line: String) {
        let parts = line.split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let active = CGWindowID(parts[1]) else { return nil }
        let members = parts[0].split(separator: " ").compactMap { field -> Member? in
            let pair = field.split(separator: "@")
            guard pair.count == 2, let id = CGWindowID(pair[0]), let pid = pid_t(pair[1]) else { return nil }
            return Member(id: id, pid: pid)
        }
        guard members.count > 1 else { return nil }
        self.init(members: members, active: active)
    }

    package var line: String { members.map { "\($0.id)@\($0.pid)" }.joined(separator: " ") + " > \(active)" }
}

extension WindowManager {
    private static let legacyTabsKey = "tabs.groups"

    package func loadTabs() {
        let defaults = Instance.defaults
        tabUI.savedTabs = (defaults.stringArray(forKey: Self.legacyTabsKey) ?? []).compactMap(SavedTabs.init)
        defaults.removeObject(forKey: Self.legacyTabsKey)
        tabUI.savedTabsUntil = Date().addingTimeInterval(SavedTabs.wait)
    }

    package func restoreTabs() {
        rejoinMaximisedTabs()
        guard !tabUI.savedTabs.isEmpty else { return }
        let late = Date() >= tabUI.savedTabsUntil
        tabUI.savedTabs.removeAll { saved in
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

    private func rejoinMaximisedTabs() {
        guard !model.maximisedTabs.isEmpty else { return }
        for id in model.rejoinMaximisedTabs(tabbable: { windows[$0]?.isFloating == false }) {
            Log.info("tabs: \(windows[id]?.bundleID ?? "window \(id)") left full screen and joined its tabs again")
        }
    }

    package func moveTabs(of id: CGWindowID, to workspace: String?,
                          _ move: (_ member: CGWindowID, _ lead: Bool) -> Void) {
        guard let group = tabs.group(of: id), let workspace else { return move(id, true) }
        let members = group.members.compactMap { member in
            windows[member].map { SavedTabs.Member(id: member, pid: $0.pid, bundleID: $0.bundleID) }
        }
        var saved = SavedTabs(members: members, active: group.active)
        saved.workspace = workspace
        tabUI.savedTabs.append(saved)
        tabUI.savedTabsUntil = Date().addingTimeInterval(SavedTabs.wait)
        for member in group.members where member != id { move(member, false) }
        move(id, true)
    }
}
