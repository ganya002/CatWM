@testable import ouch
import Testing

#if DEBUG
@Suite struct DesktopGuardLeaseTests {
    @Test func cleanExitDisarmsAllLaterRecovery() {
        var lease = DesktopGuardLease(now: 10)
        #expect(lease.receive("DONE", now: 10.1) == .finish)
        #expect(!lease.armed)
        #expect(lease.check(now: 20, parentExited: true) == .none)
        #expect(lease.check(now: 30) == .none)
    }

    @Test func heartbeatExtendsTheLeaseWithoutAnAbsoluteDeadline() {
        var lease = DesktopGuardLease(now: 0)
        for tick in 1...1_000 {
            let now = Double(tick) * 0.25
            #expect(lease.receive("PING", now: now) == .none)
            #expect(lease.check(now: now + 0.1) == .none)
        }
        #expect(lease.check(now: 251.49) == .none)
        #expect(lease.check(now: 251.5) == .restore)
        #expect(lease.check(now: 300) == .none)
    }

    @Test func parentCrashRestoresExactlyOnce() {
        var lease = DesktopGuardLease(now: 5)
        #expect(lease.check(now: 5.01, parentExited: true) == .restore)
        #expect(lease.check(now: 5.02, parentExited: true) == .none)
        #expect(lease.receive("DONE", now: 5.03) == .none)
    }

    @Test func unknownMessagesCannotKeepAnUnresponsiveParentAlive() {
        var lease = DesktopGuardLease(now: 0)
        #expect(lease.receive("P", now: 1) == .none)
        #expect(lease.receive("UNKNOWN", now: 1.4) == .none)
        #expect(lease.check(now: 1.5) == .restore)
    }
}
#endif
