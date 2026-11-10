@testable import CatWM
@testable import CatWMKit
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

    @Test func contextUpdateAfterRestoreIsRefused() {
        var lease = DesktopGuardLease(now: 0)
        let first = lease.accept(now: 1)
        #expect(first)
        #expect(lease.check(now: 2.5) == .restore)
        let late = lease.accept(now: 2.6)
        #expect(!late)
    }

    @Test func contextUpdateAfterCleanExitIsRefused() {
        var lease = DesktopGuardLease(now: 0)
        #expect(lease.receive("DONE", now: 0.1) == .finish)
        let late = lease.accept(now: 0.2)
        #expect(!late)
    }

    @Test func acceptedContextExtendsTheLease() {
        var lease = DesktopGuardLease(now: 0)
        let accepted = lease.accept(now: 1.4)
        #expect(accepted)
        #expect(lease.check(now: 2.8) == .none)
        #expect(lease.check(now: 2.9) == .restore)
    }

    @Test func unknownMessagesCannotKeepAnUnresponsiveParentAlive() {
        var lease = DesktopGuardLease(now: 0)
        #expect(lease.receive("P", now: 1) == .none)
        #expect(lease.receive("UNKNOWN", now: 1.4) == .none)
        #expect(lease.check(now: 1.5) == .restore)
    }

    @Test func aReusedGuardStillRecoversAfterAParentCrash() {
        var lease = DesktopGuardLease(now: 0)
        for transaction in 1...100 {
            let started = lease.accept(now: Double(transaction))
            let released = lease.accept(now: Double(transaction) + 0.1)
            #expect(started && released)
        }
        let started = lease.accept(now: 200)
        #expect(started)
        #expect(lease.check(now: 200.01, parentExited: true) == .restore)
        let late = lease.accept(now: 200.02)
        #expect(!late)
    }
}
#endif
