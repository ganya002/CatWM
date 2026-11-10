import AppKit
import CatWMKit

extension WindowManager {
    func shownWorkspaces() -> [ShownWorkspace] {
        guard config.virtualWorkspaces, isStarted else { return [] }
        let screens = backend.screens()
        let focus = currentScreen()?.uuid
        return (screens.filter { $0.uuid == focus } + screens.filter { $0.uuid != focus }).compactMap { screen in
            guard let nsScreen = screen.nsScreen, let workspace = shown[screen.uuid], isVirtual(workspace) else {
                return nil
            }
            return ShownWorkspace(workspace: workspace, count: tiledCount(in: workspace), screen: nsScreen)
        }
    }

    func watchCrowding(_ screens: [Screen]) {
        guard config.virtualWorkspaces, tilingEnabled, config.sortNudge > 0, isCrowded(screens) else {
            crowdWork?.cancel()
            crowdWork = nil
            return
        }
        guard crowdWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            crowdWork = nil
            if let hit = shownWorkspaces().first(where: { $0.count > self.config.sortNudge }) {
                SortNudge.shared.offer(workspace: hit.workspace, count: hit.count, on: hit.screen)
            }
        }
        crowdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    private func isCrowded(_ screens: [Screen]) -> Bool {
        screens.contains { screen in
            shown[screen.uuid].map { isVirtual($0) && tiledCount(in: $0) > config.sortNudge } ?? false
        }
    }
}

struct ShownWorkspace {
    let workspace: String
    let count: Int
    let screen: NSScreen
}
