@testable import ouch
import Testing

#if DEBUG
@Suite struct DesktopGuardReplyTests {
    @Test func contextAcknowledgementNeedsTheCompleteLine() {
        var reply = DesktopGuardReply()
        reply.receive("READY\nCONTEXT_RE")
        #expect(reply.ready)
        #expect(reply.context == 0)
        reply.receive("ADY 1")
        #expect(reply.context == 0)
        reply.receive("\n")
        #expect(reply.context == 1)
    }

    @Test func staleAcknowledgementDoesNotConfirmANewerContext() {
        var reply = DesktopGuardReply()
        reply.receive("READY\nCONTEXT_READY 1\n")
        #expect(reply.context < 2)
        reply.receive("CONTEXT_READY 2\nCONTEXT_READY 1\n")
        #expect(reply.context == 2)
    }

    @Test func malformedLinesAreNotAcknowledgements() {
        var reply = DesktopGuardReply()
        reply.receive("CONTEXT_READY\nCONTEXT_READY x\nREADY now\nDONE?\n")
        #expect(!reply.ready)
        #expect(!reply.finished)
        #expect(reply.context == 0)
    }

    @Test func finishNeedsItsOwnLine() {
        var reply = DesktopGuardReply()
        reply.receive("READY\nDONE")
        #expect(!reply.finished)
        reply.receive("\n")
        #expect(reply.finished)
    }
}
#endif
