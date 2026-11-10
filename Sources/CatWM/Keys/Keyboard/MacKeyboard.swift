import AppKit
import Carbon
import CatWMKit
import IOKit
import IOKit.ps
import MacKeysCore
import MacKeysUI

final class MacKeyboard: ObservableObject {
    static let shared = MacKeyboard()

    typealias Family = ModelID

    enum Shape { case ansi, iso, jis }

    @Published var finish: FinishID
    @Published var layout: LayoutID = .enUS
    @Published var device: MacDevice
    @Published var keys: [KeyHintKeyboard.Key] = []

    var deckLayout: MacDeckLayout { MacDeckLayout(device) }

    var setting = "auto" {
        didSet { if setting != oldValue { refresh() } }
    }

    var appearanceObserver: NSKeyValueObservation?
    private var inputSourceObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?

    static let detectedFamily: Family = {
        let name = ((productName() ?? "") + " " + (sysctl("hw.model") ?? "")).lowercased()
        if name.contains("macbook pro") || name.contains("macbookpro") { return .pro }
        if name.contains("macbook neo") || name.contains("macbookneo") { return .neo }
        if name.contains("macbook") { return .air }
        let desktops = ["imac", "mac mini", "macmini", "mac studio", "macstudio", "mac pro", "macpro"]
        for desktop in desktops where name.contains(desktop) {
            return .mk
        }
        return hasBattery() ? .air : .mk
    }()

    static let housingColor: String? = {
        for path in ["IODeviceTree:/product", "IODeviceTree:/"] {
            for key in ["housing-color", "device-color", "enclosure-color", "DeviceEnclosureColor"] {
                switch registryValue(path, key) {
                case let text as String where !text.isEmpty: return text
                case let data as Data where !data.isEmpty:
                    let text = String(bytes: data.prefix { $0 != 0 }, encoding: .utf8) ?? ""
                    if text.count > 1, text.allSatisfy({ $0.isLetter || $0 == " " }) { return text }
                    if data.count >= 3 { return String(format: "#%02x%02x%02x", data[0], data[1], data[2]) }
                case let number as Int:
                    return String(format: "#%06x", UInt32(truncatingIfNeeded: number) & 0xFFFFFF)
                default: continue
                }
            }
        }
        return nil
    }()

    init() {
        let initial = FinishID.proSpaceBlack
        finish = initial
        device = macDevice(finish: initial, layout: .enUS)
        refresh()
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
            queue: .main
        ) { [weak self] _ in self?.refresh() }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        appearanceObserver = NSApp?.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }
}

extension MacKeyboard {
    static func inputSourceID() -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    static func layout(shape: Shape, source: String) -> LayoutID {
        if shape == .jis { return .ja }
        let name = source.replacingOccurrences(of: "com.apple.keylayout.", with: "").lowercased()
        func has(_ parts: String...) -> Bool { parts.contains { name.contains($0) } }
        let mapped: LayoutID? =
            has("russian") ? .ru
            : has("korean") ? .ko
            : has("british", "irish") ? .enGB
            : has("german", "austrian") ? .de
            : has("french", "belgian") ? .fr
            : has("spanish") ? .es
            : has("swedish", "finnish") ? .svFI
            : has("norwegian") ? .no
            : has("danish") ? .da
            : has("italian") ? .it
            : has("dutch") ? .nl
            : has("swiss") ? .ch
            : has("portuguese", "brazilian") ? .pt
            : nil
        if shape == .ansi { return mapped == .ru || mapped == .ko ? mapped ?? .enUS : .enUS }
        return mapped ?? .enIntl
    }
}
