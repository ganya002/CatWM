import CoreGraphics
import Foundation

package final class WindowFillObserver {
    private struct Request {
        let ids: Set<CGWindowID>
        let done: (WindowFillObservation?) -> Void
    }
    private let queue: DispatchQueue
    private let read: (Set<CGWindowID>) -> WindowFillObservation?
    private var pending: Request?
    private var reading = false
    private var epoch = 0

    package init(queue: DispatchQueue = DispatchQueue(label: "catwm.fill-observation", qos: .userInteractive),
                 read: @escaping (Set<CGWindowID>) -> WindowFillObservation? = WindowSceneCapture.observe) {
        self.queue = queue
        self.read = read
    }

    package func request(_ ids: Set<CGWindowID>, done: @escaping (WindowFillObservation?) -> Void) {
        pending = Request(ids: ids, done: done)
        start()
    }

    package func cancel() {
        pending = nil
        epoch += 1
    }

    private func start() {
        guard !reading, let request = pending else { return }
        reading = true
        let epoch = epoch
        queue.async { [weak self, read] in
            let observation = read(request.ids)
            DispatchQueue.main.async {
                guard let self else { return }
                self.reading = false
                guard let latest = self.pending else { return }
                guard self.epoch == epoch, latest.ids == request.ids else { self.start(); return }
                self.pending = nil
                latest.done(observation)
            }
        }
    }
}
