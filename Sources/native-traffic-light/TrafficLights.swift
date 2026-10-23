import AppKit

public final class TrafficLights: NSView {
    public enum Light: CaseIterable {
        case close
        case minimize
        case zoom
    }

    public struct Buttons: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let close = Buttons(rawValue: 1)
        public static let minimize = Buttons(rawValue: 2)
        public static let zoom = Buttons(rawValue: 4)
        public static let all: Buttons = [.close, .minimize, .zoom]

        func includes(_ light: Light) -> Bool {
            switch light {
            case .close: return contains(.close)
            case .minimize: return contains(.minimize)
            case .zoom: return contains(.zoom)
            }
        }
    }

    public static let lightDiameter: CGFloat = 14
    public static let lightStride: CGFloat = 23

    public static func size(for buttons: Buttons) -> NSSize {
        let count = Light.allCases.filter { buttons.includes($0) }.count
        guard count > 0 else { return .zero }
        return NSSize(width: lightDiameter + lightStride * CGFloat(count - 1), height: lightDiameter)
    }

    public var buttons: Buttons = .all {
        didSet { layoutChanged() }
    }

    public var enabledButtons: Buttons = .all {
        didSet { needsDisplay = true }
    }

    public var isActive = true {
        didSet { needsDisplay = true }
    }

    public var zoomEntersFullScreen = false {
        didSet { needsDisplay = true }
    }

    public var onAction: ((Light) -> Void)?

    private(set) var isGroupHovered = false
    private(set) var pressedLight: Light?
    private(set) var isPressedInside = false
    private(set) var isOptionDown = false
    private var flagsMonitors: [Any] = []
    private var elements: [Light: LightElement] = [:]

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = false
    }

    public convenience init(buttons: Buttons = .all) {
        self.init(frame: NSRect(origin: .zero, size: TrafficLights.size(for: buttons)))
        self.buttons = buttons
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = false
    }

    deinit { removeFlagsMonitors() }

    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }
    public override var intrinsicContentSize: NSSize { Self.size(for: buttons) }
    public override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    var visibleLights: [Light] { Light.allCases.filter { buttons.includes($0) } }

    func frame(of light: Light) -> NSRect? {
        guard let index = visibleLights.firstIndex(of: light) else { return nil }
        let side = Self.lightDiameter
        return NSRect(x: Self.lightStride * CGFloat(index), y: (bounds.height - side) / 2, width: side, height: side)
    }

    func light(at point: NSPoint) -> Light? {
        visibleLights.first { frame(of: $0)?.contains(point) == true }
    }

    var groupRect: NSRect {
        let size = Self.size(for: buttons)
        return NSRect(x: 0, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    var isDark: Bool {
        let match = effectiveAppearance.bestMatch(from: [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua
        ])
        return match == .darkAqua || match == .accessibilityHighContrastDarkAqua
    }

    func setHovered(_ hovered: Bool) {
        guard hovered != isGroupHovered else { return }
        isGroupHovered = hovered
        if hovered {
            isOptionDown = NSEvent.modifierFlags.contains(.option)
            installFlagsMonitors()
        } else {
            removeFlagsMonitors()
            isOptionDown = false
        }
        needsDisplay = true
    }

    func setPressed(_ light: Light?, inside: Bool) {
        pressedLight = light
        isPressedInside = inside
        needsDisplay = true
    }

    func setOptionDown(_ down: Bool) {
        guard down != isOptionDown else { return }
        isOptionDown = down
        needsDisplay = true
    }

    private func layoutChanged() {
        invalidateIntrinsicContentSize()
        elements.removeAll()
        updateTrackingAreas()
        needsDisplay = true
    }

    private func installFlagsMonitors() {
        guard flagsMonitors.isEmpty else { return }
        let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.setOptionDown(event.modifierFlags.contains(.option))
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.setOptionDown(event.modifierFlags.contains(.option))
        }
        flagsMonitors = [local, global].compactMap(\.self)
    }

    private func removeFlagsMonitors() {
        flagsMonitors.forEach(NSEvent.removeMonitor)
        flagsMonitors.removeAll()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            isGroupHovered = false
            removeFlagsMonitors()
        }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    public override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        super.updateTrackingAreas()
        addTrackingArea(NSTrackingArea(rect: groupRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    public override func mouseEntered(with _: NSEvent) { setHovered(true) }
    public override func mouseExited(with _: NSEvent) { setHovered(false) }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        return light(at: convert(point, from: superview)) == nil ? nil : self
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let light = light(at: point), enabledButtons.includes(light) else { return }
        setPressed(light, inside: true)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let light = pressedLight, let rect = frame(of: light) else { return }
        let inside = rect.contains(convert(event.locationInWindow, from: nil))
        guard inside != isPressedInside else { return }
        setPressed(light, inside: inside)
    }

    public override func mouseUp(with event: NSEvent) {
        guard let light = pressedLight, let rect = frame(of: light) else { return }
        let inside = rect.contains(convert(event.locationInWindow, from: nil))
        setPressed(nil, inside: false)
        if inside { onAction?(light) }
    }

    func glyph(for light: Light) -> GlyphKind {
        switch light {
        case .close: return .close
        case .minimize: return .minimize
        case .zoom: return zoomEntersFullScreen && !isOptionDown ? .zoomArrows : .zoomPlus
        }
    }

    public override func draw(_: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dark = isDark
        for light in visibleLights {
            guard let rect = frame(of: light) else { continue }
            let enabled = enabledButtons.includes(light)
            let pressed = pressedLight == light && isPressedInside && enabled
            let showsGlyph = enabled && (pressed || isGroupHovered)
            let art: LightArt
            if pressed {
                art = .pressed(light, dark: dark)
            } else if !enabled {
                art = .grey(dark: dark)
            } else if isActive || isGroupHovered {
                art = .normal(light, dark: dark)
            } else {
                art = .grey(dark: dark)
            }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            art.draw(in: ctx, center: center, diameter: Self.lightDiameter)
            if showsGlyph {
                let kind = glyph(for: light)
                kind.shape.draw(kind, color: kind.color(dark: dark, pressed: pressed), in: ctx, center: center)
            }
        }
    }

    public override func isAccessibilityElement() -> Bool { false }

    public override func accessibilityChildren() -> [Any]? {
        visibleLights.map { light in
            if let element = elements[light] { return element }
            let element = LightElement(light: light, owner: self)
            elements[light] = element
            return element
        }
    }

    func perform(_ light: Light) {
        guard enabledButtons.includes(light) else { return }
        onAction?(light)
    }
}

final class LightElement: NSAccessibilityElement {
    let light: TrafficLights.Light
    weak var owner: TrafficLights?

    init(light: TrafficLights.Light, owner: TrafficLights) {
        self.light = light
        self.owner = owner
        super.init()
    }

    var subrole: NSAccessibility.Subrole {
        switch light {
        case .close: return .closeButton
        case .minimize: return .minimizeButton
        case .zoom: return owner?.zoomEntersFullScreen == true ? .fullScreenButton : .zoomButton
        }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { subrole }
    override func accessibilityRoleDescription() -> String? {
        NSAccessibility.Role.button.description(with: subrole)
    }
    override func accessibilityLabel() -> String? { accessibilityRoleDescription() }
    override func accessibilityParent() -> Any? { owner }
    override func isAccessibilityEnabled() -> Bool { owner?.enabledButtons.includes(light) ?? false }

    override func accessibilityFrame() -> NSRect {
        guard let owner, let rect = owner.frame(of: light), let window = owner.window else { return .zero }
        return window.convertToScreen(owner.convert(rect, to: nil))
    }

    override func accessibilityPerformPress() -> Bool {
        guard let owner, owner.enabledButtons.includes(light) else { return false }
        owner.perform(light)
        return true
    }
}
