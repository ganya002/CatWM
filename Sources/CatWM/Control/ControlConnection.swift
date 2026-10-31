import Foundation

final class ControlConnection {
    static let maxLine = 1 << 20
    static let maxPending = 1 << 20

    private let descriptor: Int32
    private let queue: DispatchQueue
    private var reader: DispatchSourceRead?
    private var writer: DispatchSourceWrite?
    private var writing = false
    private var inbox = Data()
    private var outbox = Data()
    private var closed = false
    private let onLine: (ControlConnection, Data) -> Void
    private let onClose: (ControlConnection) -> Void

    init(descriptor: Int32, onLine: @escaping (ControlConnection, Data) -> Void,
         onClose: @escaping (ControlConnection) -> Void) {
        self.descriptor = descriptor
        self.onLine = onLine
        self.onClose = onClose
        queue = DispatchQueue(label: "catwm.control.\(descriptor)", qos: .userInitiated)
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        var quiet: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &quiet, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit {
        guard !closed else { return }
        if !writing { writer?.resume() }
        writer?.cancel()
        if let reader { reader.cancel() } else { Darwin.close(descriptor) }
    }

    func start() {
        queue.async { [self] in
            let reader = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            reader.setEventHandler { [weak self] in self?.readAvailable() }
            reader.setCancelHandler { [descriptor] in Darwin.close(descriptor) }
            self.reader = reader
            reader.resume()
            let writer = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: queue)
            writer.setEventHandler { [weak self] in self?.flush() }
            self.writer = writer
        }
    }

    func send(_ data: Data) {
        queue.async { [self] in
            guard !closed else { return }
            outbox.append(data)
            guard outbox.count <= Self.maxPending else { return finish() }
            flush()
        }
    }

    func close() { queue.async { [self] in finish() } }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let count = read(descriptor, &buffer, buffer.count)
        if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) { return finish() }
        guard count > 0 else { return }
        inbox.append(contentsOf: buffer[0..<count])
        while let newline = inbox.firstIndex(of: 0x0A) {
            let line = inbox[inbox.startIndex..<newline]
            guard line.count <= Self.maxLine else { return finish() }
            inbox = Data(inbox[inbox.index(after: newline)...])
            if !line.isEmpty { onLine(self, Data(line)) }
        }
        if inbox.count > Self.maxLine { finish() }
    }

    private func flush() {
        while !outbox.isEmpty {
            let written = outbox.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            if written > 0 {
                outbox.removeFirst(written)
            } else if written < 0, errno == EAGAIN {
                if !writing { writing = true; writer?.resume() }
                return
            } else if written < 0, errno == EINTR {
                continue
            } else {
                return finish()
            }
        }
        if writing { writing = false; writer?.suspend() }
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        if !writing { writer?.resume() }
        writer?.cancel()
        if let reader { reader.cancel() } else { Darwin.close(descriptor) }
        reader = nil
        writer = nil
        onClose(self)
    }
}
