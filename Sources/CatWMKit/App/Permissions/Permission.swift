import AppKit

package enum Permission: CaseIterable {
    case accessibility
    case inputMonitoring
    case screenRecording
    case fullDiskAccess

    package var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        case .screenRecording: ScreenRecording.shared.isGranted
        case .fullDiskAccess: NotificationDatabase.isReadable
        }
    }

    package var id: String {
        switch self {
        case .accessibility: "accessibility"
        case .inputMonitoring: "inputMonitoring"
        case .screenRecording: "screenRecording"
        case .fullDiskAccess: "fullDiskAccess"
        }
    }

    package var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .screenRecording: "Screen & System Audio Recording"
        case .fullDiskAccess: "Full Disk Access"
        }
    }
}

extension Process {
    package static func runTool(_ path: String, _ args: [String], wait: Bool = true) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.info("run \(path) failed: \(error)")
            return
        }
        if wait { process.waitUntilExit() }
    }
}
