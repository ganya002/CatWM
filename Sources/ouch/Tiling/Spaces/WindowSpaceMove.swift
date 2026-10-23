import Foundation

struct WindowSpaceMove {
    var membership: () -> [UInt64]
    var submit: () -> Bool
    var isOnScreen: () -> Bool
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func run(to target: UInt64, waitUntilOnScreen: Bool, completion: @escaping (Bool) -> Void) {
        guard target != 0 else { completion(false); return }
        let arrived = membership() == [target]
        if arrived, !waitUntilOnScreen || isOnScreen() { completion(true); return }
        guard arrived || submit() else { completion(false); return }
        let deadline = now() + 0.5
        var retries = 0
        func check() {
            if membership() == [target], !waitUntilOnScreen || isOnScreen() { completion(true); return }
            let remaining = deadline - now()
            guard remaining > 0 else { completion(false); return }
            let delay = retries < 4 ? 0.001 : 0.004
            retries += 1
            schedule(min(delay, remaining), check)
        }
        check()
    }
}
