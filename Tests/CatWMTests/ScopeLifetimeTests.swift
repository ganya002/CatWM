@testable import CatWM
@testable import CatWMKit
import Foundation
import os
import Testing

@Suite struct ScopeLifetimeTests {
    func spawn(_ path: String) throws -> (process: Process, input: Pipe) {
        let input = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.standardInput = input
        try process.run()
        return (process, input)
    }

    @Test func aScopeThatNamesLaunchdIsRefused() {
        #expect(WindowScope(pids: [1]).refusal?.contains("pid 1") == true)
        #expect(WindowScope(pids: [20, 1]).refusal != nil)
        #expect(WindowScope(pids: [20, 21]).refusal == nil)
    }

    @Test func onlyTheDefaultInstanceMayRelaunchItself() throws {
        let home = FileManager.default.temporaryDirectory
        #expect(try #require(InstancePaths(id: nil, home: home)).mayRelaunchItself)
        #expect(try !#require(InstancePaths(id: "perf-x", home: home)).mayRelaunchItself)
    }

    @Test func aRunningProcessIsAliveAndAReapedOneIsNot() throws {
        let (process, input) = try spawn("/bin/cat")
        #expect(ScopeLifetime.isAlive(process.processIdentifier))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(!ScopeLifetime.isAlive(process.processIdentifier))
        #expect(ScopeLifetime.isAlive(getpid()))
    }

    @Test func theInstanceStaysWhileOnePidOfTheScopeLives() {
        let count = OSAllocatedUnfairLock(initialState: 0)
        let lifetime = ScopeLifetime(pids: [20, 21], alive: { $0 == 21 }, ended: { count.withLock { $0 += 1 } })
        lifetime.start()
        #expect(count.withLock { $0 } == 0)
        lifetime.stop()
    }

    @Test(.timeLimit(.minutes(1))) func theInstanceEndsOnceWhenEveryPidOfTheScopeExits() async throws {
        let first = try spawn("/bin/cat")
        let second = try spawn("/bin/cat")
        defer {
            for owner in [first, second] {
                try? owner.input.fileHandleForWriting.close()
                owner.process.waitUntilExit()
            }
        }
        let (ends, end) = AsyncStream.makeStream(of: Void.self)
        let count = OSAllocatedUnfairLock(initialState: 0)
        let lifetime = ScopeLifetime(pids: [first.process.processIdentifier, second.process.processIdentifier]) {
            count.withLock { $0 += 1 }
            end.yield()
        }
        lifetime.start()
        kill(first.process.processIdentifier, SIGKILL)
        kill(second.process.processIdentifier, SIGKILL)
        var iterator = ends.makeAsyncIterator()
        await iterator.next()
        #expect(count.withLock { $0 } == 1)
        lifetime.stop()
    }

    @Test(.timeLimit(.minutes(1))) func aScopeThatIsAlreadyGoneEndsAtOnce() async throws {
        let (process, input) = try spawn("/bin/cat")
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let (ends, end) = AsyncStream.makeStream(of: Void.self)
        let lifetime = ScopeLifetime(pids: [process.processIdentifier]) { end.yield() }
        lifetime.start()
        var iterator = ends.makeAsyncIterator()
        await iterator.next()
        lifetime.stop()
    }
}
