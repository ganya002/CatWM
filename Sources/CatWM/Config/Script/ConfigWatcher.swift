import CoreServices
import Foundation

final class ConfigWatcher {
    private let changed: ([String]) -> Void
    private var stream: FSEventStreamRef?
    private(set) var folders: [String] = []

    init(changed: @escaping ([String]) -> Void) { self.changed = changed }

    deinit { stop() }

    func watch(_ folders: [URL]) {
        let paths = Array(Set(folders.map { $0.resolvingSymlinksInPath().path })).sorted()
        guard paths != self.folders else { return }
        stop()
        self.folders = paths
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info, let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String]
            else { return }
            Unmanaged<ConfigWatcher>.fromOpaque(info).takeUnretainedValue().changed(Array(list.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.03, flags)
        else { return Log.info("config: can't watch \(paths.joined(separator: ", "))") }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        folders = []
    }
}
