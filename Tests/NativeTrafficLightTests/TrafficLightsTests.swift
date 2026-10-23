import AppKit
@testable import NativeTrafficLight
import Testing

@MainActor
@Suite struct TrafficLightsTests {
    private func makeHost(_ buttons: TrafficLights.Buttons = .all) -> (NSWindow, TrafficLights) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let lights = TrafficLights(buttons: buttons)
        lights.frame.origin = NSPoint(x: 20, y: 20)
        window.contentView?.addSubview(lights)
        return (window, lights)
    }

    private func event(_ type: NSEvent.EventType, _ point: NSPoint, in lights: TrafficLights) -> NSEvent {
        let location = lights.convert(point, to: nil)
        return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                                  windowNumber: lights.window?.windowNumber ?? 0, context: nil,
                                  eventNumber: 0, clickCount: 1, pressure: 1) ?? NSEvent()
    }

    @Test func sizeMatchesTheSystemGroup() {
        #expect(TrafficLights.size(for: .all) == NSSize(width: 60, height: 14))
        #expect(TrafficLights.size(for: .close) == NSSize(width: 14, height: 14))
        #expect(TrafficLights.size(for: [.close, .zoom]) == NSSize(width: 37, height: 14))
        #expect(TrafficLights.size(for: []) == .zero)
    }

    @Test func lightsSitOnTheSystemGrid() {
        let (_, lights) = makeHost()
        #expect(lights.frame(of: .close) == NSRect(x: 0, y: 0, width: 14, height: 14))
        #expect(lights.frame(of: .minimize) == NSRect(x: 23, y: 0, width: 14, height: 14))
        #expect(lights.frame(of: .zoom) == NSRect(x: 46, y: 0, width: 14, height: 14))
    }

    @Test func aLoneCloseLightSitsAtTheOrigin() {
        let (_, lights) = makeHost(.close)
        #expect(lights.visibleLights == [.close])
        #expect(lights.frame(of: .close) == NSRect(x: 0, y: 0, width: 14, height: 14))
        #expect(lights.frame(of: .zoom) == nil)
    }

    @Test func hitRectsStopAtTheGaps() {
        let (_, lights) = makeHost()
        #expect(lights.light(at: NSPoint(x: 7, y: 7)) == .close)
        #expect(lights.light(at: NSPoint(x: 30, y: 7)) == .minimize)
        #expect(lights.light(at: NSPoint(x: 53, y: 7)) == .zoom)
        #expect(lights.light(at: NSPoint(x: 18, y: 7)) == nil)
        #expect(lights.light(at: NSPoint(x: 41, y: 7)) == nil)
    }

    @Test func hoverIsOneStateForTheWholeGroup() {
        let (_, lights) = makeHost()
        #expect(!lights.isGroupHovered)
        lights.setHovered(true)
        #expect(lights.isGroupHovered)
        lights.setHovered(false)
        #expect(!lights.isGroupHovered)
    }

    @Test func theGroupTrackingAreaCoversTheGaps() {
        let (_, lights) = makeHost()
        lights.updateTrackingAreas()
        #expect(lights.trackingAreas.count == 1)
        #expect(lights.trackingAreas.first?.rect == NSRect(x: 0, y: 0, width: 60, height: 14))
        #expect(lights.trackingAreas.first?.options.contains(.activeAlways) == true)
    }

    @Test func theActionFiresOnMouseUpInside() {
        let (_, lights) = makeHost()
        var fired: [TrafficLights.Light] = []
        lights.onAction = { fired.append($0) }
        lights.mouseDown(with: event(.leftMouseDown, NSPoint(x: 30, y: 7), in: lights))
        #expect(lights.pressedLight == .minimize)
        #expect(lights.isPressedInside)
        #expect(fired.isEmpty)
        lights.mouseUp(with: event(.leftMouseUp, NSPoint(x: 30, y: 7), in: lights))
        #expect(fired == [.minimize])
        #expect(lights.pressedLight == nil)
    }

    @Test func draggingOutUnpressesAndReleaseDoesNotFire() {
        let (_, lights) = makeHost()
        var fired: [TrafficLights.Light] = []
        lights.onAction = { fired.append($0) }
        lights.mouseDown(with: event(.leftMouseDown, NSPoint(x: 7, y: 7), in: lights))
        lights.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 100, y: 40), in: lights))
        #expect(!lights.isPressedInside)
        lights.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 8, y: 8), in: lights))
        #expect(lights.isPressedInside)
        lights.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 100, y: 40), in: lights))
        lights.mouseUp(with: event(.leftMouseUp, NSPoint(x: 100, y: 40), in: lights))
        #expect(fired.isEmpty)
        #expect(lights.pressedLight == nil)
    }

    @Test func aDisabledLightIgnoresClicks() {
        let (_, lights) = makeHost()
        lights.enabledButtons = [.close, .zoom]
        var fired = 0
        lights.onAction = { _ in fired += 1 }
        lights.mouseDown(with: event(.leftMouseDown, NSPoint(x: 30, y: 7), in: lights))
        lights.mouseUp(with: event(.leftMouseUp, NSPoint(x: 30, y: 7), in: lights))
        #expect(fired == 0)
        #expect(lights.pressedLight == nil)
    }

    @Test func aFirstClickOnAnInactivePanelIsAccepted() {
        let (_, lights) = makeHost()
        #expect(lights.acceptsFirstMouse(for: nil))
        #expect(!lights.mouseDownCanMoveWindow)
    }

    @Test func theOptionKeyChangesTheZoomMarkOfAFullScreenLight() {
        let (_, lights) = makeHost()
        #expect(lights.glyph(for: .zoom) == .zoomPlus)
        lights.zoomEntersFullScreen = true
        #expect(lights.glyph(for: .zoom) == .zoomArrows)
        lights.setOptionDown(true)
        #expect(lights.glyph(for: .zoom) == .zoomPlus)
        lights.setOptionDown(false)
        #expect(lights.glyph(for: .zoom) == .zoomArrows)
    }

    @Test func theAppearanceDecidesTheArt() {
        let (_, lights) = makeHost()
        lights.appearance = NSAppearance(named: .aqua)
        #expect(!lights.isDark)
        lights.appearance = NSAppearance(named: .darkAqua)
        #expect(lights.isDark)
        lights.appearance = NSAppearance(named: .accessibilityHighContrastDarkAqua)
        #expect(lights.isDark)
    }

    @Test func eachLightIsAnAccessibleButtonWithTheSystemSubrole() throws {
        let (_, lights) = makeHost()
        let children = try #require(lights.accessibilityChildren() as? [NSAccessibilityElement])
        #expect(children.count == 3)
        #expect(children.map { $0.accessibilityRole() } == [.button, .button, .button])
        #expect(children.map { $0.accessibilitySubrole() } == [.closeButton, .minimizeButton, .zoomButton])
        for child in children {
            #expect(child.accessibilityRoleDescription() == NSAccessibility.Role.button
                .description(with: child.accessibilitySubrole()))
            #expect(child.accessibilityLabel() == child.accessibilityRoleDescription())
            #expect(child.isAccessibilityEnabled())
        }
        #expect(!lights.isAccessibilityElement())
    }

    @Test func aFullScreenZoomLightUsesTheFullScreenSubrole() throws {
        let (_, lights) = makeHost()
        lights.zoomEntersFullScreen = true
        let children = try #require(lights.accessibilityChildren() as? [NSAccessibilityElement])
        #expect(children[2].accessibilitySubrole() == .fullScreenButton)
    }

    @Test func pressingThroughAccessibilityFiresTheAction() throws {
        let (_, lights) = makeHost()
        lights.enabledButtons = [.close]
        var fired: [TrafficLights.Light] = []
        lights.onAction = { fired.append($0) }
        let children = try #require(lights.accessibilityChildren() as? [NSAccessibilityElement])
        #expect(children[0].accessibilityPerformPress())
        #expect(!children[1].accessibilityPerformPress())
        #expect(!children[1].isAccessibilityEnabled())
        #expect(fired == [.close])
    }

    @Test func noToolTipByDefault() {
        let (_, lights) = makeHost()
        #expect(lights.toolTip == nil)
    }
}
