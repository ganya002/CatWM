import Foundation
import os

package final class ControlConnection: Sendable {
    package static let maxLine = 1 << 20
    package static let maxPending = 1 << 20

    private struct State {
        var reader: DispatchSourceRead?
        var writer: DispatchSourceWrite?
        var writing = false
        var inbox = Data()
        var outbox = Data()
        var closed = false
    }

    private let descriptor: Int32
    private let queue: DispatchQueue
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let onLine: @Sendable (ControlConnection, Data) -> Void
    private let onClose: @Sendable (ControlConnection) -> Void

    package init(descriptor: Int32, onLine: @escaping @Sendable (ControlConnection, Data) -> Void,
                 onClose: @escaping @Sendable (ControlConnection) -> Void) {
        self.descriptor = descriptor
        self.onLine = onLine
        self.onClose = onClose
        queue = DispatchQueue(label: "catwm.control.\(descriptor)", qos: .userInitiated)
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        var quiet: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &quiet, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit {
        state.withLock { state in
            guard !state.closed else { return }
            if !state.writing { state.writer?.resume() }
            state.writer?.cancel()
            if let reader = state.reader { reader.cancel() } else { Darwin.close(descriptor) }
        }
    }

    package func start() {
        queue.async { [self] in
            let reader = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            reader.setEventHandler { [weak self] in self?.readAvailable() }
            reader.setCancelHandler { [descriptor] in Darwin.close(descriptor) }
            let writer = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: queue)
            writer.setEventHandler { [weak self] in self?.flush() }
            state.withLock { state in
                state.reader = reader
                state.writer = writer
            }
            reader.resume()
        }
    }

    private enum SendAction { case drop, finish, flush }

    package func send(_ data: Data) {
        queue.async { [self] in
            let action = state.withLock { state -> SendAction in
                guard !state.closed else { return .drop }
                state.outbox.append(data)
                return state.outbox.count > Self.maxPending ? .finish : .flush
            }
            switch action {
            case .drop: break
            case .finish: finish()
            case .flush: flush()
            }
        }
    }

    package func close() { queue.async { [self] in finish() } }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let count = read(descriptor, &buffer, buffer.count)
        if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) { return finish() }
        guard count > 0 else { return }
        let received = buffer[0..<count]
        let (lines, overflow) = state.withLock { state -> ([Data], Bool) in
            state.inbox.append(contentsOf: received)
            var lines: [Data] = []
            while let newline = state.inbox.firstIndex(of: 0x0A) {
                let line = state.inbox[state.inbox.startIndex..<newline]
                guard line.count <= Self.maxLine else { return (lines, true) }
                state.inbox = Data(state.inbox[state.inbox.index(after: newline)...])
                if !line.isEmpty { lines.append(Data(line)) }
            }
            return (lines, state.inbox.count > Self.maxLine)
        }
        for line in lines { onLine(self, line) }
        if overflow { finish() }
    }

    private func flush() {
        let failed = state.withLock { state -> Bool in
            while !state.outbox.isEmpty {
                let written = state.outbox.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
                if written > 0 {
                    state.outbox.removeFirst(written)
                } else if written < 0, errno == EAGAIN {
                    if !state.writing { state.writing = true; state.writer?.resume() }
                    return false
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return true
                }
            }
            if state.writing { state.writing = false; state.writer?.suspend() }
            return false
        }
        if failed { finish() }
    }

    private func finish() {
        let closing = state.withLock { state -> Bool in
            guard !state.closed else { return false }
            state.closed = true
            if !state.writing { state.writer?.resume() }
            state.writer?.cancel()
            if let reader = state.reader { reader.cancel() } else { Darwin.close(descriptor) }
            state.reader = nil
            state.writer = nil
            return true
        }
        if closing { onClose(self) }
    }
}
