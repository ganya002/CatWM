// Compile as main.swift alongside WindowServerUpdates.swift. No WindowServer calls are made.
import AppKit
final class Calls {
    let lock = NSLock()
    var disabled = 0, enabled = 0
    func disable() -> Bool { lock.withLock { disabled += 1 }; return true }
    func enable() { lock.withLock { enabled += 1 } }
    var counts: [Int] { lock.withLock { [disabled, enabled] } }
}
let calls = Calls()
let batches = WindowServerUpdates(maximumHold: 0.04, disable: calls.disable, enable: calls.enable)
let first = batches.begin()!
let second = batches.begin()!
precondition(calls.counts == [1, 0])
first.finish(); first.finish()
precondition(calls.counts == [1, 0], "Overlapping import must keep the batch alive")
second.finish()
precondition(calls.counts == [1, 1], "Last lease must release exactly once")
let timedOut = batches.begin()!
usleep(80_000) // main thread intentionally cannot service a timer
precondition(calls.counts == [2, 2], "Watchdog must release without the main run loop")
let next = batches.begin()!
timedOut.finish()
precondition(calls.counts == [3, 2], "An expired lease must not release a newer batch")
next.finish()
precondition(calls.counts == [3, 3])
do { _ = batches.begin()! }
precondition(calls.counts == [4, 4], "Dropping the lease must release it")
let unavailable = WindowServerUpdates(disable: { false }, enable: { fatalError("Must not enable after failed disable") })
precondition(unavailable.begin() == nil)
print("PASS: overlapping imports, idempotent release, off-main watchdog, stale leases, dropped leases, unavailable API")
