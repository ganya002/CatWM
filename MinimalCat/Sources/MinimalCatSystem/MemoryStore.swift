import Foundation
import MinimalCatCore

/// Keeps the display memory on disk, so layouts survive a restart of Minimal Cat or of the Mac.
public struct MemoryStore {
    public let url: URL
    private var written: DisplayMemory?

    public init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Minimal Cat")) {
        url = folder.appendingPathComponent("memory.json")
    }

    public mutating func load() -> DisplayMemory {
        let memory = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(DisplayMemory.self, from: $0) }
        written = memory
        return memory ?? DisplayMemory()
    }

    public mutating func write(_ memory: DisplayMemory) {
        guard memory != written else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(memory).write(to: url, options: .atomic)
            written = memory
        } catch {
            NSLog("Minimal Cat: could not save layouts: \(error)")
        }
    }
}
