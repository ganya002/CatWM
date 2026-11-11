import AppKit
import QuartzCore
import ScreenCaptureKit

package final class WindowLiveBuffers {
    package init() {}
    private struct Prepared {
        let frames: [CGWindowID: CGRect]
        let capture: WindowSceneCapture
        let time: CFTimeInterval
    }
    private let captureQueue = DispatchQueue(label: "catwm.live-background", qos: .userInitiated)
    private var prepared: Prepared?
    private var preparing = false
    private struct Request {
        let frames: [CGWindowID: CGRect]
        let screens: [Screen]
        let excluding: Set<CGWindowID>
    }
    private var pending: Request?
    private var streams: [CGWindowID: NativeWindowStream] = [:]
    private var requested: Set<CGWindowID> = []
    private var loading = false
    private var capacity = CGSize.zero
    private var rate = 5
    package var refresh: (() -> Void)?

    package func frame(_ id: CGWindowID) -> NativeWindowFrame? {
        requested.contains(id) ? streams[id]?.frame : nil
    }

    package func pace(active: Bool) {
        rate = active ? 120 : 5
        streams.values.forEach { $0.pace(rate) }
    }

    package func stop() {
        refresh = nil
        prepared = nil
        pending = nil
        warm([], capacity: capacity)
    }

    package func capture(moving frames: [CGWindowID: CGRect])
        -> (capture: WindowSceneCapture, frames: [CGWindowID: CGRect])? {
        guard let prepared, CACurrentMediaTime() - prepared.time < 5,
              frames.allSatisfy({ prepared.frames[$0.key]?.approxEqual($0.value, tolerance: 0.25) == true }),
              prepared.frames.keys.allSatisfy({ frame($0) != nil }) else {
            return nil
        }
        return (prepared.capture, prepared.frames)
    }

    package func prepare(frames: [CGWindowID: CGRect], screens: [Screen], excluding: Set<CGWindowID>) {
        guard !frames.isEmpty else { return }
        if let prepared, prepared.frames == frames, CACurrentMediaTime() - prepared.time < 1 { return }
        guard !preparing else { pending = Request(frames: frames, screens: screens, excluding: excluding); return }
        preparing = true
        captureQueue.async { [weak self] in
            let capture = WindowSceneCapture.take(frames: frames, screens: screens, excluding: excluding,
                                                  includeWindowImages: false)
            DispatchQueue.main.async {
                guard let self else { return }
                self.preparing = false
                if let capture, Set(frames.keys).isSubset(of: self.requested) {
                    self.prepared = Prepared(frames: frames, capture: capture, time: CACurrentMediaTime())
                    Log.debug("live-window: prepared background \(frames.count)")
                } else if capture == nil {
                    Log.debug("live-window: background changed during capture")
                }
                if let next = self.pending {
                    self.pending = nil
                    self.prepare(frames: next.frames, screens: next.screens, excluding: next.excluding)
                }
            }
        }
    }

    package func warm(_ ids: Set<CGWindowID>, capacity: CGSize) {
        requested = ids
        self.capacity = capacity
        guard !loading, Set(streams.keys) != ids, ids.isEmpty || CGPreflightScreenCaptureAccess() else { return }
        loading = true
        Task { @MainActor [self] in
            defer {
                loading = false
                if requested != ids { warm(requested, capacity: self.capacity) }
            }
            for id in Set(streams.keys).subtracting(ids) { await streams.removeValue(forKey: id)?.stop() }
            guard !ids.isEmpty else {
                Log.debug("live-window: streams stopped")
                return
            }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                for window in content.windows where ids.contains(window.windowID) && streams[window.windowID] == nil {
                    let stream = NativeWindowStream()
                    try await stream.start(window: window, capacity: capacity, rate: rate)
                    streams[window.windowID] = stream
                    Log.debug("live-window: streaming \(window.windowID)")
                }
            } catch { Log.info("live-window: preparation failed: \(error)") }
        }
    }
}
