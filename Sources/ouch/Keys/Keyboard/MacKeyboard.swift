import AppKit
import Carbon
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

    static let detectedFamily: Family = {
        let name = ((productName() ?? "") + " " + (sysctl("hw.model") ?? "")).lowercased()
        if name.contains("macbook pro") || name.contains("macbookpro") { return .pro }
        if name.contains("macbook neo") || name.contains("macbookneo") { return .neo }
        if name.contains("macbook") { return .air }
        for desktop in ["imac", "mac mini", "macmini", "mac studio", "macstudio", "mac pro", "macpro"] where name.contains(desktop) {
            return .mk
        }
        return hasBattery() ? .air : .mk
    }()

    static let housingColor: String? = {
        for path in ["IODeviceTree:/product", "IODeviceTree:/"] {
            for key in ["housing-color", "device-color", "enclosure-color", "DeviceEnclosureColor"] {
                switch registryValue(path, key) {
                case let s as String where !s.isEmpty: return s
                case let d as Data where !d.isEmpty:
                    let text = String(decoding: d.prefix { $0 != 0 }, as: UTF8.self)
                    if text.count > 1, text.allSatisfy({ $0.isLetter || $0 == " " }) { return text }
                    if d.count >= 3 { return String(format: "#%02x%02x%02x", d[0], d[1], d[2]) }
                case let n as NSNumber: return String(format: "#%06x", n.uint32Value & 0xFFFFFF)
                default: continue
                }
            }
        }
        return nil
    }()

    init() {
        let f = FinishID.proSpaceBlack
        finish = f
        device = macDevice(finish: f, layout: .enUS)
        refresh()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        appearanceObserver = NSApp?.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

}
