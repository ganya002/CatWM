// Overlays: the screen-edge effect shown while a mode (submap) is on.
import AppKit
import SwiftUI

// MARK: - Panels

/// Screen-edge effect while a mode (submap) is on, so you can tell keys are going to ouch and not the
/// app. A click-through panel on every screen. The style is `mode-effect` in the config (Settings: Motion ›
/// Advanced); `ouch modefx <style>` previews one and `ouch modefx all` plays them one after another.
final class ModeFX {
    static let shared = ModeFX()

    enum Style: String, CaseIterable {
        case draw, ripple, corners, none

        var title: String {
            switch self {
            case .draw: "Draw"
            case .ripple: "Ripple"
            case .corners: "Corners"
            case .none: "None"
            }
        }
    }

    /// The configured style; previews show others without changing it.
    var style: Style = .draw
    private let model = ModeFXModel()
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var hideWork: DispatchWorkItem?
    private var demo: [DispatchWorkItem] = []

    func setActive(_ on: Bool) {
        setActive(on, style: style)
    }

    private func setActive(_ on: Bool, style: Style) {
        guard on != model.active else { return }
        hideWork?.cancel()
        if on {
            guard style != .none else { return }
            model.style = style
            layoutPanels()
            model.cursor = NSEvent.mouseLocation
            model.active = true
            PerfMonitor.track("ui:modefx-\(style)", for: 0.6)
            // A turn later, so a view that just appeared for a new style sees the trigger change
            // (one built with the new value already in place wouldn't animate).
            DispatchQueue.main.async { [weak self] in self?.model.enters += 1 }
        } else {
            model.active = false
            let work = DispatchWorkItem { [weak self] in self?.panels.values.forEach { $0.orderOut(nil) } }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    /// `modefx <style>` or `modefx all`.
    func command(_ args: [String]) {
        demo.forEach { $0.cancel() }
        demo = []
        switch args.first?.lowercased() {
        case "all":
            for (i, s) in Style.allCases.filter({ $0 != .none }).enumerated() {
                schedule(Double(i) * 2.6) { [weak self] in self?.preview(s) }
            }
        case let name? where Style(rawValue: name) != nil:
            preview(Style(rawValue: name)!)
        default:
            Log.info("modefx: styles are \(Style.allCases.map(\.rawValue).joined(separator: ", ")), or all")
        }
    }

    private func preview(_ s: Style) {
        setActive(false)
        hideWork?.cancel()
        HUD.shared.show(s.rawValue.capitalized, on: NSScreen.main)
        schedule(0.05) { [weak self] in self?.setActive(true, style: s) }
        schedule(1.9) { [weak self] in
            if Hotkeys.shared.submap.isEmpty { self?.setActive(false) }
        }
    }

    private func schedule(_ delay: Double, _ f: @escaping () -> Void) {
        let w = DispatchWorkItem(block: f)
        demo.append(w)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    private func layoutPanels() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            seen.insert(id)
            let p = panels[id] ?? makePanel(screen)
            panels[id] = p
            // A reused panel's view still has the origin and corners of where its screen used to be.
            if let host = p.contentView as? NSHostingView<ModeFXView> { host.rootView = view(for: screen) }
            p.setFrame(screen.frame, display: false)
            p.orderFrontRegardless()
        }
        for (id, p) in panels where !seen.contains(id) {
            p.orderOut(nil)
            panels[id] = nil
        }
    }

    private func makePanel(_ screen: NSScreen) -> NSPanel {
        let p = OuchPanel(role: .fullscreenFX, frame: screen.frame)
        p.contentView = NSHostingView(rootView: view(for: screen))
        return p
    }

    /// A fullscreen app's window is square and, on a notched screen, sits below a black menu bar band.
    /// There the border goes round the window instead of the screen and the notch.
    private func view(for screen: NSScreen) -> ModeFXView {
        let uuid = screen.displayID.flatMap { CGDisplayCreateUUIDFromDisplayID($0) }
            .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
        if let uuid, Spaces.isFullscreen(display: uuid) {
            return ModeFXView(model: model, radius: 0, origin: screen.frame.origin, topInset: screen.safeAreaInsets.top)
        }
        return ModeFXView(model: model, radius: Self.topCornerRadius(screen), origin: screen.frame.origin,
                          notchHalfWidth: Self.notchHalfWidth(screen), notchHeight: Self.notchHeight(screen))
    }

    private typealias CornerRadiiFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Double>?, UnsafeMutablePointer<Double>?,
                                                      UnsafeMutablePointer<Double>?, UnsafeMutablePointer<Double>?) -> Int32
    private static let cornerRadii: CornerRadiiFn? = symbol("SLSDisplayGetCornerRadii",
                                                            in: "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")

    /// How round the screen's top corners are, in points, so the border follows them instead of being
    /// cut off. Built-in MacBook displays round only the top (about 20pt on notched ones); the bottom and
    /// external displays are square. WindowServer knows the exact value per display; the notch is the
    /// fallback guess.
    /// Half the width of the camera notch, or 0 on screens without one. Drawn borders start at its edges.
    static func notchHalfWidth(_ screen: NSScreen) -> CGFloat {
        guard screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea else { return 0 }
        return max(0, (r.minX - l.maxX) / 2)
    }

    /// Height of the camera notch, or 0 on screens without one.
    static func notchHeight(_ screen: NSScreen) -> CGFloat {
        notchHalfWidth(screen) > 0 ? (screen.auxiliaryTopLeftArea?.height ?? screen.safeAreaInsets.top) : 0
    }

    static func topCornerRadius(_ screen: NSScreen) -> CGFloat {
        var radii = [Double](repeating: 0, count: 4) // the bottom two, then the top two
        if let f = cornerRadii, let id = screen.displayID,
           radii.withUnsafeMutableBufferPointer({ f(id, $0.baseAddress, $0.baseAddress! + 1, $0.baseAddress! + 2, $0.baseAddress! + 3) }) == 0 {
            return radii.max() ?? 0
        }
        return screen.safeAreaInsets.top > 0 ? 20 : 0
    }

}

private extension NSScreen {
    var displayID: CGDirectDisplayID? { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }
}

// MARK: - Views

final class ModeFXModel: ObservableObject {
    @Published var active = false
    @Published var enters = 0
    @Published var style: ModeFX.Style = .draw
    @Published var color = Theme.accent
    /// Where the pointer was on entering, in global (bottom-left) coordinates, for the ripple.
    var cursor: CGPoint = .zero
}

struct ModeFXView: View {
    @ObservedObject var model: ModeFXModel
    let radius: CGFloat
    let origin: CGPoint
    var notchHalfWidth: CGFloat = 0
    var notchHeight: CGFloat = 0
    /// Space at the top of the screen the effect leaves out: the black menu bar band over a fullscreen app.
    var topInset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width: geo.size.width, height: max(0, geo.size.height - topInset))
            effect(size: size)
                .frame(width: size.width, height: size.height)
                .offset(y: topInset)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// The screen's outline: rounded at the top only, like the built-in display.
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .circular)
    }
    /// Borders are drawn this much thicker on the side facing the screen edge or the notch. The extra part is
    /// off screen or behind the notch, so what shows is the same, but the line meets the notch whatever its
    /// exact curve is and leaves no sliver of gap.
    private var tuck: CGFloat { notchHalfWidth > 0 ? 6 : 0 }
    private var notchCutout: some View {
        NotchCutout(halfWidth: notchHalfWidth, height: notchHeight).fill(style: FillStyle(eoFill: true))
    }
    private var c: Color { model.color }
    private var on: Bool { model.active }

    /// The finished screen border: two mirrored halves that begin at the notch edges, so nothing runs under it.
    private func border(width: CGFloat) -> some View {
        ZStack {
            ForEach([false, true], id: \.self) { mirrored in
                DrawnHalf(radius: radius, inset: (width - tuck) / 2, notchHalfWidth: notchHalfWidth, notchHeight: notchHeight)
                    .stroke(c, style: StrokeStyle(lineWidth: width + tuck, lineCap: .butt, lineJoin: .miter))
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            }
        }
    }

    @ViewBuilder private func effect(size: CGSize) -> some View {
        if reduceMotion && model.style != .none {
            // No motion: just the finished border, faded in.
            border(width: 4)
                .opacity(on ? 1 : 0).animation(.easeOut(duration: 0.15), value: on)
        } else {
            animated(size: size)
        }
    }

    @ViewBuilder private func animated(size: CGSize) -> some View {
        switch model.style {
        case .ripple:
            // A ring from the pointer out past the screen corners; the border lights as it arrives.
            let p = CGPoint(x: model.cursor.x - origin.x, y: size.height - (model.cursor.y - origin.y))
            let reach = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
                .map { hypot($0.x - p.x, $0.y - p.y) }.max() ?? 1000
            Color.clear.keyframeAnimator(initialValue: Ripple(), trigger: model.enters) { _, v in
                ZStack {
                    Circle().strokeBorder(c.opacity(0.85), lineWidth: max(1, 30 * (1 - v.t)))
                        .blur(radius: 6)
                        .frame(width: reach * 2 * v.t, height: reach * 2 * v.t)
                        .position(p)
                        .opacity(v.t >= 1 ? 0 : 1 - v.t * 0.6)
                        .mask(notchCutout) // the ring stops at the notch; the border below tucks into it
                    border(width: 3.5).opacity(v.edge)
                }
                .clipShape(shape)
            } keyframes: { _ in
                KeyframeTrack(\.t) {
                    CubicKeyframe(0, duration: 0.001)
                    CubicKeyframe(1, duration: 0.55)
                }
                KeyframeTrack(\.edge) {
                    CubicKeyframe(0, duration: 0.3)
                    CubicKeyframe(1, duration: 0.2)
                }
            }
            .opacity(on ? 1 : 0).animation(.easeOut(duration: on ? 0 : 0.25), value: on)

        case .corners:
            Color.clear.keyframeAnimator(initialValue: 0.0, trigger: model.enters) { _, k in
                ZStack {
                    ForEach(0..<4) { i in
                        Bracket(radius: 6)
                            .stroke(c, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 70, height: 70)
                            .offset(x: -40 * (1 - k), y: -40 * (1 - k))
                            .rotationEffect(.degrees(Double(i) * 90))
                            .frame(width: 70, height: 70)
                            .position(corner(i, size))
                    }
                }
                .opacity(min(1, k * 1.5))
                .mask(notchCutout)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0, duration: 0.001)
                    SpringKeyframe(1, duration: 0.5, spring: Spring(response: 0.32, dampingRatio: 0.6))
                }
            }
            .opacity(on ? 1 : 0).animation(.easeOut(duration: on ? 0 : 0.2), value: on)

        case .draw:
            // The border draws itself from the top centre, both ways, with a bright head.
            Color.clear.keyframeAnimator(initialValue: 0.0, trigger: model.enters) { _, k in
                ZStack {
                    ForEach([false, true], id: \.self) { mirrored in
                        let half = DrawnHalf(radius: radius, inset: (4 - tuck) / 2, notchHalfWidth: notchHalfWidth, notchHeight: notchHeight)
                        ZStack {
                            half.trim(from: 0, to: k).stroke(c, style: StrokeStyle(lineWidth: 4 + tuck, lineCap: .round, lineJoin: .miter))
                            half.trim(from: max(0, k - 0.06), to: k)
                                .stroke(c, style: StrokeStyle(lineWidth: 14, lineCap: .round)).blur(radius: 8)
                                .opacity(k >= 1 ? 0 : 1)
                        }
                        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                    }
                }
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0, duration: 0.001)
                    CubicKeyframe(1, duration: 0.45)
                }
            }
            .opacity(on ? 1 : 0).animation(.easeOut(duration: on ? 0 : 0.25), value: on)

        case .none:
            EmptyView()
        }
    }

    private func corner(_ i: Int, _ s: CGSize) -> CGPoint {
        let m: CGFloat = 35 + 8
        return [CGPoint(x: m, y: m), CGPoint(x: s.width - m, y: m),
                CGPoint(x: s.width - m, y: s.height - m), CGPoint(x: m, y: s.height - m)][i]
    }

    private struct Ripple { var t: CGFloat = 0; var edge: Double = 0 }
}

// MARK: - Shapes

/// The notch's outline, in points: the side walls meet the screen top through a concave flare, and the
/// bottom corners are rounded.
private enum Notch {
    static let bottomRadius: CGFloat = 8
    static let flareRadius: CGFloat = 6
}

/// The whole rect with the notch cut out of the top centre (fill it even-odd as a mask).
private struct NotchCutout: Shape {
    let halfWidth: CGFloat
    let height: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        guard halfWidth > 0 else { return p }
        let l = rect.midX - halfWidth, r = rect.midX + halfWidth, top = rect.minY
        let rb = Notch.bottomRadius, rf = Notch.flareRadius, k: CGFloat = 0.5523
        p.move(to: CGPoint(x: l - rf, y: top))
        p.addCurve(to: CGPoint(x: l, y: top + rf), control1: CGPoint(x: l - rf + k * rf, y: top), control2: CGPoint(x: l, y: top + rf - k * rf))
        p.addArc(tangent1End: CGPoint(x: l, y: top + height), tangent2End: CGPoint(x: r, y: top + height), radius: rb)
        p.addArc(tangent1End: CGPoint(x: r, y: top + height), tangent2End: CGPoint(x: r, y: top), radius: rb)
        p.addLine(to: CGPoint(x: r, y: top + rf))
        p.addCurve(to: CGPoint(x: r + rf, y: top), control1: CGPoint(x: r, y: top + rf - k * rf), control2: CGPoint(x: r + rf - k * rf, y: top))
        p.closeSubpath()
        return p
    }
}

/// A top-left corner bracket; rotated for the other three.
private struct Bracket: Shape {
    let radius: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: radius)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

/// The right half of the screen outline, from top centre round to bottom centre; mirrored for the left.
/// Only the top corner is rounded, like the screen.
private struct DrawnHalf: Shape {
    let radius: CGFloat
    let inset: CGFloat
    /// With a notch, the path starts under it and curves round it instead of running behind it.
    var notchHalfWidth: CGFloat = 0
    var notchHeight: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let rad = max(0, radius - inset)
        var p = Path()
        if notchHalfWidth > 0 {
            // Hug the notch, just outside its outline: out from under its middle, round the bottom corner,
            // up the wall and out along the flare to the top edge.
            let x = r.midX + notchHalfWidth + inset, y = rect.minY + notchHeight + inset
            p.move(to: CGPoint(x: r.midX, y: y))
            p.addArc(tangent1End: CGPoint(x: x, y: y), tangent2End: CGPoint(x: x, y: r.minY), radius: Notch.bottomRadius + inset)
            p.addArc(tangent1End: CGPoint(x: x, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: max(0.5, Notch.flareRadius - inset))
        } else {
            p.move(to: CGPoint(x: r.midX, y: r.minY))
        }
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: rad)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}
