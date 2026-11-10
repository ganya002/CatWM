@testable import CatWM
@testable import CatWMKit
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

    @Test func aReleaseNeedsItsCompleteMatchingGeneration() {
        var reply = DesktopGuardReply()
        reply.receive("READY\nCONTEXT_READY 1\nRELEA")
        #expect(reply.released == -1)
        reply.receive("SED 1")
        #expect(reply.released == -1)
        reply.receive("\nCONTEXT_READY 2\nRELEASED 0\n")
        #expect(reply.context == 2)
        #expect(reply.released == 1)
        reply.receive("RELEASED 2\nRELEASED x\n")
        #expect(reply.released == 2)
    }

    @Test func restorationNeedsACompleteAcknowledgementForTheCurrentContext() {
        var reply = DesktopGuardReply()
        reply.receive("RESTORE_SUBMITTED\nRESTORE_SUBMITTED x\nRESTORE_SUB")
        #expect(reply.restoreSubmitted == -1)
        reply.receive("MITTED 1")
        #expect(reply.restoreSubmitted == -1)
        reply.receive("\nCONTEXT_READY 2\nRESTORE_SUBMITTED 0\n")
        #expect(reply.restoreSubmitted == 1 && reply.restoreSubmitted < reply.context)
        reply.receive("RESTORE_SUBMITTED 2\nRESTORE_SUBMITTED 1\n")
        #expect(reply.restoreSubmitted == 2)
        #expect(reply.released == -1 && !reply.finished)
    }
}
#endif
