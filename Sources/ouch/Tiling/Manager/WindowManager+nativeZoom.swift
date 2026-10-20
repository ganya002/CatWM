import AppKit

extension WindowManager {
    func adoptNativeZoom(_ window: Window) {
        scanner.run(window.pid) { [weak self] in
            let frame = window.element.frame
            DispatchQueue.main.async {
                guard let self, self.windows[window.id] === window, !window.isFloating,
                      !self.animator.isBusy(window.id), !frame.isNull,
                      NSEvent.pressedMouseButtons & 1 == 0,
                      let screen = self.screen(containing: frame),
                      self.shown[screen.uuid] == self.workspaceOf[window.id] else { return }
                let state = self.state(for: screen)
                let usable = self.usableRect(screen)
                let fills = frame.width >= usable.width * 0.95 && frame.height >= usable.height * 0.95
                if fills, state.zoomed != window.id {
                    state.zoomed = window.id
                } else if !fills, state.zoomed == window.id {
                    state.zoomed = nil
                }
                self.scheduleRefresh()
            }
        }
    }
}
