// Tiling: moves windows to another macOS Space through SkyLight.
import AppKit
import MachO
import ObjectiveC

/// Ouch's in-process binding to WindowServer's asynchronous move operation.
/// Symbol lookup follows the technique in WhichSpace (MIT; see ThirdPartyNotices.txt).
/// No helper library or external window manager is needed.
enum NativeSpaceMove {
    private typealias Perform = @convention(c) (UnsafeMutableRawPointer) -> Int64
    private typealias Allocate = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
    private typealias Initialize = @convention(c) (UnsafeMutableRawPointer, Selector, CFArray, UInt64) -> UnsafeMutableRawPointer?
    private typealias Release = @convention(c) (UnsafeMutableRawPointer, Selector) -> Void

    private struct Binding {
        let type: AnyClass
        let perform: Perform
        let allocate: Allocate
        let initialize: Initialize
        let release: Release
    }

    private static let initializer = NSSelectorFromString("initWithWindows:spaceID:")
    private static let allocate = NSSelectorFromString("alloc")
    private static let release = NSSelectorFromString("release")
    private static let binding: Binding? = {
        guard dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) != nil else { return nil }
        let name = "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation"
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), String(name.dropFirst())) ?? localSymbol(name),
              let type = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation"),
              let allocMethod = class_getClassMethod(type, allocate),
              let initMethod = class_getInstanceMethod(type, initializer),
              let releaseMethod = class_getInstanceMethod(type, release) else { return nil }
        return Binding(type: type, perform: unsafeBitCast(address, to: Perform.self),
                       allocate: unsafeBitCast(method_getImplementation(allocMethod), to: Allocate.self),
                       initialize: unsafeBitCast(method_getImplementation(initMethod), to: Initialize.self),
                       release: unsafeBitCast(method_getImplementation(releaseMethod), to: Release.self))
    }()

    static var isAvailable: Bool { binding != nil }

    /// The request is asynchronous. The caller must verify actual Space membership.
    static func move(window: CGWindowID, to space: UInt64) -> Bool {
        guard let binding, let allocated = binding.allocate(binding.type, allocate) else { return false }
        let windows = [NSNumber(value: window)] as CFArray
        // An initializer that returns nil has already released its receiver.
        guard let operation = binding.initialize(allocated, initializer, windows, space) else { return false }
        defer { binding.release(operation, release) }
        _ = binding.perform(operation)
        return true
    }

    private static func adding(_ a: UInt, _ b: UInt) -> UInt? {
        let (value, overflow) = a.addingReportingOverflow(b)
        return overflow ? nil : value
    }

    private static func sliding(_ address: UInt64, by slide: Int) -> UInt? {
        guard let address = UInt(exactly: address) else { return nil }
        if slide >= 0 { return adding(address, UInt(slide)) }
        let (value, overflow) = address.subtractingReportingOverflow(slide.magnitude)
        return overflow ? nil : value
    }

    /// The dispatcher has internal linkage. Read its address from SkyLight's loaded
    /// Mach-O symbol table, rejecting tables outside the image's __LINKEDIT segment.
    private static func localSymbol(_ name: String) -> UnsafeMutableRawPointer? {
        for i in 0..<_dyld_image_count() {
            guard let path = _dyld_get_image_name(i), String(cString: path).hasSuffix("/SkyLight"),
                  let header = _dyld_get_image_header(i), header.pointee.magic == MH_MAGIC_64 else { continue }
            let base = UnsafeRawPointer(header)
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
                    let segmentName = withUnsafeBytes(of: &segment.segname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                    if segmentName == "__LINKEDIT" { linkedit = segment }
                } else if command.cmd == LC_SYMTAB, command.cmdsize >= MemoryLayout<symtab_command>.size {
                    symbols = pointer.load(as: symtab_command.self)
                }
                offset += Int(command.cmdsize)
            }
            guard let segment = linkedit, let table = symbols, table.nsyms > 0, table.strsize > 0,
                  let start = sliding(segment.vmaddr, by: _dyld_get_image_vmaddr_slide(i)),
                  let length = UInt(exactly: segment.vmsize), let end = adding(start, length),
                  let fileOffset = UInt(exactly: segment.fileoff), start >= fileOffset,
                  let entries = adding(start - fileOffset, UInt(table.symoff)),
                  let entriesEnd = adding(entries, UInt(table.nsyms) * UInt(MemoryLayout<nlist_64>.size)),
                  let strings = adding(start - fileOffset, UInt(table.stroff)),
                  let stringsEnd = adding(strings, UInt(table.strsize)),
                  entries >= start, entriesEnd <= end, strings >= start, stringsEnd <= end else { return nil }
            let expected = Array(name.utf8) + [0]
            for index in 0..<Int(table.nsyms) {
                guard let pointer = UnsafeRawPointer(bitPattern: entries + UInt(index * MemoryLayout<nlist_64>.size)) else { return nil }
                let entry = pointer.load(as: nlist_64.self)
                let stringOffset = entry.n_un.n_strx
                guard stringOffset > 0, stringOffset < table.strsize, entry.n_value != 0,
                      expected.count <= Int(table.strsize - stringOffset),
                      let string = UnsafeRawPointer(bitPattern: strings + UInt(stringOffset)) else { continue }
                let bytes = UnsafeRawBufferPointer(start: string, count: expected.count)
                guard bytes.elementsEqual(expected) else { continue }
                guard let address = sliding(entry.n_value, by: _dyld_get_image_vmaddr_slide(i)) else { return nil }
                return UnsafeMutableRawPointer(bitPattern: address)
            }
        }
        return nil
    }
}
