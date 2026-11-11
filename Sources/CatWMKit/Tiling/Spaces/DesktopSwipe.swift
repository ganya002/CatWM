import AppKit

package enum DesktopSwipe {
    package static let tag: Int64 = 0x4F55_5052
    package static func field(_ number: UInt32) -> CGEventField { unsafeBitCast(number, to: CGEventField.self) }
    package static var augmented: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 }

    package static func naturalScroll() -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString,
                                         kCFPreferencesAnyApplication) as? Bool ?? true
    }

    package static func post(right: Bool) -> Bool {
        guard RealInput.allows("Desktop swipe"),
              let sequence = events(right: right, augmented: augmented, natural: naturalScroll()) else { return false }
        sequence.forEach { $0.post(tap: .cgSessionEventTap) }
        return true
    }

    package enum Phase: Int64 { case began = 1, changed = 2, ended = 4, cancelled = 8 }
    package struct Sample {
        package let phase: Phase
        package let progress: Double
        package let velocity: Double
    }

    package static func events(right: Bool, augmented: Bool, natural: Bool) -> [CGEvent]? {
        var sequence: [CGEvent] = []
        for phase: Phase in [.began, .changed, .ended] {
            let velocity = augmented ? (phase == .ended ? 9999.0 : 0) : 2000
            let specification = Sample(phase: phase, progress: 0.0001, velocity: velocity)
            guard let sample = trackingEvents(right: right, sample: specification,
                                              augmented: augmented, natural: natural) else { return nil }
            sequence.append(contentsOf: sample)
        }
        return sequence
    }

    package static func trackingEvents(right: Bool, sample: Sample, augmented: Bool, natural: Bool) -> [CGEvent]? {
        let phase = sample.phase, progress = sample.progress, velocity = sample.velocity
        guard progress.isFinite, (0...2).contains(progress), velocity.isFinite, abs(velocity) <= 10_000,
              let event = CGEvent(source: nil) else { return nil }
        let sign = (right ? 1.0 : -1.0) * (augmented ? (natural ? -1 : 1) : 1)
        event.setIntegerValueField(field(55), value: 30)
        event.setIntegerValueField(field(110), value: 23)
        event.setIntegerValueField(field(123), value: 1)
        event.setIntegerValueField(field(132), value: phase.rawValue)
        event.setDoubleValueField(field(124), value: sign * progress)
        event.setDoubleValueField(field(125), value: 0.1)
        event.setDoubleValueField(field(129), value: sign * velocity)
        if !augmented { event.setDoubleValueField(field(130), value: sign * velocity) }
        guard let posted = augmented ? augment(event) : event else { return nil }
        posted.setIntegerValueField(.eventSourceUserData, value: tag)
        guard augmented else { return [posted] }
        guard let companion = CGEvent(source: nil) else { return nil }
        companion.setIntegerValueField(field(55), value: 29)
        companion.setIntegerValueField(.eventSourceUserData, value: tag)
        return [posted, companion]
    }

    private static func augment(_ event: CGEvent) -> CGEvent? {
        guard let data = event.data else { return nil }
        var bytes = [UInt8](data as Data)
        guard bytes.starts(with: [0, 0, 0, 2]) else { return nil }
        let phase = event.getIntegerValueField(field(132))
        let velocity = event.getDoubleValueField(field(129))
        let hasVelocity = velocity != 0 || phase == 4
        var payload: [UInt8] = []
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) }
        }
        func fixed(_ value: Double) -> Int32 {
            let scaled = Int32(value * 65536)
            return scaled == 0 && value != 0 ? (value > 0 ? 1 : -1) : scaled
        }
        append(event.timestamp == 0 ? mach_absolute_time() : event.timestamp)
        append(UInt64(0))
        append(UInt32(0))
        append(UInt32(0))
        append(UInt32(hasVelocity ? 2 : 1))
        append(UInt32(40))
        append(UInt32(23))
        append(UInt32(truncatingIfNeeded: phase) << 24)
        append(UInt32(0))
        append(fixed(event.getDoubleValueField(field(125))))
        append(Int32(0))
        append(Int32(0))
        append(UInt32(0))
        append(UInt16(1))
        append(UInt16(3))
        append(fixed(event.getDoubleValueField(field(124))))
        if hasVelocity {
            append(UInt32(28))
            append(UInt32(9))
            append(UInt32(0))
            append(UInt32(1))
            append(fixed(velocity))
            append(Int32(0))
            append(Int32(0))
        }
        bytes.append(contentsOf: [UInt8(payload.count >> 8), UInt8(payload.count & 255), 0x10, 0x6D])
        bytes.append(contentsOf: payload)
        return CGEvent(withDataAllocator: nil, data: Data(bytes) as CFData)
    }
}
