import AppKit

extension WindowManager {
    package func handleNativeSwipe(_ sample: DesktopGestureTap.Sample) {
        if sample.phase == 1 { desktops.nativeGestureSign = nil }
        if desktops.nativeGestureSign == nil, abs(sample.progress) > 0.001, !nativeDesktop.isRunning {
            guard let screen = backend.screens().first(where: { $0.frame.contains(mouseLocation()) }) else { return }
            updateNativeCatalog(backend.screens())
            let space = backend.currentSpace(display: screen.uuid)
            guard let source = desktops.nativeCatalog.entry(space: space) else { return }
            let direction = sample.progress > 0 ? 1 : -1
            guard let name = desktops.nativeCatalog.step(from: source.name, by: direction),
                  let target = desktops.nativeCatalog.entry(name) else { return }
            desktops.nativeGestureSign = Double(direction)
            configureNativeController(focusing: nil, focus: true, quiet: false)
            nativeDesktop.beginGesture(.init(workspace: name, display: target.display, space: target.space))
        }
        guard let sign = desktops.nativeGestureSign else { return }
        let progress = min(1, max(0, sample.progress * sign))
        nativeDesktop.scrub(progress)
        if sample.phase == 4 || sample.phase == 8 {
            nativeDesktop.endGesture(commit: sample.phase != 8 && (progress >= 0.5 || sample.velocity * sign > 0.5))
            desktops.nativeGestureSign = nil
        }
    }
}
