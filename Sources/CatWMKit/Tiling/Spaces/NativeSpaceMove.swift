import AppKit
import Foundation
import MachO
import ObjectiveC

package enum NativeSpaceMove {
    private typealias Perform = @convention(c) (UnsafeMutableRawPointer) -> Int64
    private typealias Allocate = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
    private typealias Initialize = @convention(c) (
        UnsafeMutableRawPointer, Selector, CFArray, UInt64
    ) -> UnsafeMutableRawPointer?
    private typealias Release = @convention(c) (UnsafeMutableRawPointer, Selector) -> Void

    private struct Binding {
        package let type: AnyClass
        package let perform: Perform
        package let allocate: Allocate
        package let initialize: Initialize
        package let release: Release
    }

    private static let initializer = NSSelectorFromString("initWithWindows:spaceID:")
    private static let allocate = NSSelectorFromString("alloc")
    private static let release = NSSelectorFromString("release")
    private static let binding: Binding? = {
        guard dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) != nil else {
            return nil
        }
        let name = "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperation"
            + "P47SLSAsynchronousBridgedWindowManagementOperation"
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), String(name.dropFirst()))
                ?? localSymbol(name),
              let type = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation"),
              let allocMethod = class_getClassMethod(type, allocate),
              let initMethod = class_getInstanceMethod(type, initializer),
              let releaseMethod = class_getInstanceMethod(type, release) else { return nil }
        return Binding(type: type, perform: unsafeBitCast(address, to: Perform.self),
                       allocate: unsafeBitCast(method_getImplementation(allocMethod), to: Allocate.self),
                       initialize: unsafeBitCast(method_getImplementation(initMethod), to: Initialize.self),
                       release: unsafeBitCast(method_getImplementation(releaseMethod), to: Release.self))
    }()

    package static var isAvailable: Bool { binding != nil }

    package static func move(window: CGWindowID, to space: UInt64) -> Bool {
        guard let binding, let allocated = binding.allocate(binding.type, allocate) else { return false }
        let windows = [window] as CFArray
        guard let operation = binding.initialize(allocated, initializer, windows, space) else { return false }
        defer { binding.release(operation, release) }
        _ = binding.perform(operation)
        return true
    }

    private static let synchronousAddress: UnsafeMutableRawPointer? = {
        let name = "__ZL54_SLSPerformSynchronousBridgedWindowManagementOperation"
            + "P46SLSSynchronousBridgedWindowManagementOperation"
        return dlsym(UnsafeMutableRawPointer(bitPattern: -2), String(name.dropFirst())) ?? localSymbol(name)
    }()

    package static func isDisplayIdle(_ display: String) -> Bool {
        typealias Initialize = @convention(c) (UnsafeMutableRawPointer, Selector, CFString) -> UnsafeMutableRawPointer?
        typealias Read = @convention(c) (AnyObject, Selector) -> Bool
        let value = NSSelectorFromString("boolValue")
        let result = performSynchronous("SLSBridgedManagedDisplayIsAnimatingOperation",
                                        selector: "initWithDisplayIdentifier:") { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, display as CFString)
        }
        guard let result,
              let read = class_getInstanceMethod(object_getClass(result), value) else { return false }
        return !unsafeBitCast(method_getImplementation(read), to: Read.self)(result, value)
    }

    package static func performSynchronous(
        _ name: String, selector nameOfSelector: String,
        initialize: (UnsafeMutableRawPointer, Selector, IMP) -> UnsafeMutableRawPointer?
    ) -> AnyObject? {
        typealias Perform = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<AnyObject>?
        let selector = NSSelectorFromString(nameOfSelector)
        guard let binding, let address = synchronousAddress, let type = NSClassFromString(name),
              let method = class_getInstanceMethod(type, selector),
              let allocated = binding.allocate(type, allocate),
              let operation = initialize(allocated, selector, method_getImplementation(method)) else { return nil }
        defer { binding.release(operation, release) }
        return unsafeBitCast(address, to: Perform.self)(operation)?.takeUnretainedValue()
    }

    package static func perform(
        _ name: String, selector nameOfSelector: String,
        initialize: (UnsafeMutableRawPointer, Selector, IMP) -> UnsafeMutableRawPointer?
    ) -> Bool {
        let selector = NSSelectorFromString(nameOfSelector)
        guard let binding, let type = NSClassFromString(name),
              let method = class_getInstanceMethod(type, selector),
              let allocated = binding.allocate(type, allocate),
              let operation = initialize(allocated, selector, method_getImplementation(method)) else { return false }
        defer { binding.release(operation, release) }
        _ = binding.perform(operation)
        return true
    }

    private static func adding(_ base: UInt, _ amount: UInt) -> UInt? {
        let (value, overflow) = base.addingReportingOverflow(amount)
        return overflow ? nil : value
    }

    private static func sliding(_ address: UInt64, by slide: Int) -> UInt? {
        guard let address = UInt(exactly: address) else { return nil }
        if slide >= 0 { return adding(address, UInt(slide)) }
        let (value, overflow) = address.subtractingReportingOverflow(slide.magnitude)
        return overflow ? nil : value
    }

    private struct SymbolTable {
        package let entries: UInt
        package let strings: UInt
        package let count: Int
        package let stringSize: UInt32
    }

    private static func localSymbol(_ name: String) -> UnsafeMutableRawPointer? {
        let expected = Array(name.utf8) + [0]
        for i in 0..<_dyld_image_count() {
            guard let path = _dyld_get_image_name(i), String(cString: path).hasSuffix("/SkyLight"),
                  let header = _dyld_get_image_header(i), header.pointee.magic == MH_MAGIC_64 else { continue }
            let slide = _dyld_get_image_vmaddr_slide(i)
            guard let table = symbolTable(UnsafeRawPointer(header), slide: slide) else { return nil }
            for index in 0..<table.count {
                let entryAddress = table.entries + UInt(index * MemoryLayout<nlist_64>.size)
                guard let pointer = UnsafeRawPointer(bitPattern: entryAddress) else { return nil }
                let entry = pointer.load(as: nlist_64.self)
                let stringOffset = entry.n_un.n_strx
                guard stringOffset > 0, stringOffset < table.stringSize, entry.n_value != 0,
                      expected.count <= Int(table.stringSize - stringOffset),
                      let string = UnsafeRawPointer(bitPattern: table.strings + UInt(stringOffset)) else { continue }
                let bytes = UnsafeRawBufferPointer(start: string, count: expected.count)
                guard bytes.elementsEqual(expected) else { continue }
                guard let address = sliding(entry.n_value, by: slide) else { return nil }
                return UnsafeMutableRawPointer(bitPattern: address)
            }
        }
        return nil
    }

    private static func loadCommands(
        _ base: UnsafeRawPointer
    ) -> (linkedit: segment_command_64, symbols: symtab_command)? {
        let image = base.load(as: mach_header_64.self)
        var linkedit: segment_command_64?
        var symbols: symtab_command?
        var offset = 0
        let commands = base.advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<image.ncmds {
            guard offset <= Int(image.sizeofcmds) - MemoryLayout<load_command>.size else { return nil }
            let pointer = commands.advanced(by: offset)
            let command = pointer.load(as: load_command.self)
            guard command.cmdsize >= MemoryLayout<load_command>.size,
                  Int(command.cmdsize) <= Int(image.sizeofcmds) - offset else { return nil }
            if command.cmd == LC_SEGMENT_64, command.cmdsize >= MemoryLayout<segment_command_64>.size {
                var segment = pointer.load(as: segment_command_64.self)
                let segmentName = withUnsafeBytes(of: &segment.segname) {
                    String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8)
                }
                if segmentName == "__LINKEDIT" { linkedit = segment }
            } else if command.cmd == LC_SYMTAB, command.cmdsize >= MemoryLayout<symtab_command>.size {
                symbols = pointer.load(as: symtab_command.self)
            }
            offset += Int(command.cmdsize)
        }
        guard let linkedit, let symbols else { return nil }
        return (linkedit, symbols)
    }

    private static func symbolTable(_ base: UnsafeRawPointer, slide: Int) -> SymbolTable? {
        guard let (segment, table) = loadCommands(base),
              table.nsyms > 0, table.strsize > 0,
              let start = sliding(segment.vmaddr, by: slide),
              let length = UInt(exactly: segment.vmsize), let end = adding(start, length),
              let fileOffset = UInt(exactly: segment.fileoff), start >= fileOffset,
              let entries = adding(start - fileOffset, UInt(table.symoff)),
              let entriesEnd = adding(entries, UInt(table.nsyms) * UInt(MemoryLayout<nlist_64>.size)),
              let strings = adding(start - fileOffset, UInt(table.stroff)),
              let stringsEnd = adding(strings, UInt(table.strsize)),
              entries >= start, entriesEnd <= end, strings >= start, stringsEnd <= end else { return nil }
        return SymbolTable(entries: entries, strings: strings, count: Int(table.nsyms), stringSize: table.strsize)
    }
}

package struct WindowSpaceMove {
    package var membership: () -> [UInt64]
    package var submit: () -> Bool
    package var isOnScreen: () -> Bool
    package var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    package var schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter( // style-ok: polls Space membership, which has no event
            deadline: .now() + delay, execute: work
        )
    }

    package func run(to target: UInt64, waitUntilOnScreen: Bool, completion: @escaping (Bool) -> Void) {
        guard target != 0 else { completion(false); return }
        let arrived = membership() == [target]
        if arrived, !waitUntilOnScreen || isOnScreen() { completion(true); return }
        guard arrived || submit() else { completion(false); return }
        let deadline = now() + 0.5
        var retries = 0
        func check() {
            if membership() == [target], !waitUntilOnScreen || isOnScreen() { completion(true); return }
            let remaining = deadline - now()
            guard remaining > 0 else { completion(false); return }
            let delay = retries < 4 ? 0.001 : 0.004
            retries += 1
            schedule(min(delay, remaining), check)
        }
        check()
    }
}
