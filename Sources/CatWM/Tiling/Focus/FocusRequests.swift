import CoreGraphics
import Foundation

struct FocusRequests {
    struct PendingFocus {
        let id: CGWindowID
        let pid: pid_t
        let origin: pid_t?
        let request: UUID
        var executed = false
    }

    struct FocusCommand {
        let pid: pid_t
        let dispatcher: String
        let arg: String
        let inMode: Bool
    }

    var pendingFocus: PendingFocus?
    var focusCommands: [FocusCommand] = []
    var waitingRefocus: (workspace: String, pid: pid_t)?
    var refocusAfterClose: String?
    var focusEcho: FocusEcho?
    var reportedFocus: (pid: pid_t, id: CGWindowID?)?
    var focusReader = FocusReader()
    var focusObservation = 0
    var focusReads: Set<pid_t> = []
}
