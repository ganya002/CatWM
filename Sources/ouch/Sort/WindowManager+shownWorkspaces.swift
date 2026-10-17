import AppKit

extension WindowManager {
    func shownWorkspaces() -> [(workspace: String, count: Int, screen: NSScreen)] {
        guard config.virtualWorkspaces, isStarted else { return [] }
        let screens = Screen.all()
        let focus = currentScreen()?.uuid
        return (screens.filter { $0.uuid == focus } + screens.filter { $0.uuid != focus }).compactMap { s in
            guard let ws = shown[s.uuid], isVirtual(ws) else { return nil }
            return (ws, tiledCount(in: ws), s.ns)
        }
    }

    func watchCrowding(_ screens: [Screen]) {
        guard config.virtualWorkspaces, tilingEnabled, config.sortNudge > 0,
              screens.contains(where: { s in shown[s.uuid].map { isVirtual($0) && tiledCount(in: $0) > config.sortNudge } ?? false })
        else { crowdWork?.cancel(); crowdWork = nil; return }
        guard crowdWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            crowdWork = nil
            if let hit = shownWorkspaces().first(where: { $0.count > self.config.sortNudge }) {
                SortNudge.shared.offer(workspace: hit.workspace, count: hit.count, on: hit.screen)
            }
        }
        crowdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
}
