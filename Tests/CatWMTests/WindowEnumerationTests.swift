import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct WindowEnumerationTests {
    @Test func partialWindowListIncludesOtherAccessibleWindows() {
        let app = AXUIElementCreateApplication(-1)
        let listed = AXUIElementCreateApplication(-2)
        let child = AXUIElementCreateApplication(-3)
        let main = AXUIElementCreateApplication(-4)
        let focused = AXUIElementCreateApplication(-5)
        let found = WindowScanner.listedElements(app) { _, attribute in
            switch attribute {
            case kAXWindowsAttribute: return [listed] as CFArray
            case kAXChildrenAttribute: return [child] as CFArray
            case kAXMainWindowAttribute: return main
            case kAXFocusedWindowAttribute: return focused
            default: return nil
            }
        }
        #expect(found == [listed, child, main, focused])
    }

    @Test func unsupportedAttributesDoNotDiscardListedWindows() {
        let app = AXUIElementCreateApplication(-1)
        let found = WindowScanner.listedElements(app) { _, attribute in
            attribute == kAXWindowsAttribute ? [app] as CFArray : nil
        }
        #expect(found == [app])
    }

    @Test @MainActor func aKnownWindowStaysVisibleWhenTheAppOmitsIt() async {
        let fake = FakeBackend()
        fake.addScreen()
        let id = fake.addWindow()
        let scanner = WindowScanner(read: { job, discovered in
            var scan = fake.scan(job, discovered: discovered)
            scan.listed.removeAll { job.known[$0] != nil }
            return scan
        }, readDesktop: { fake.desktop(known: $0) }, readApplications: { fake.applications() })
        var config = Config.parse(defaultText)
        config.virtualWorkspaces = false
        config.animate = false
        config.mouseFollowsFocus = false
        config.focusFollowsMouse = false
        let manager = WindowManager(backend: fake, config: config, scanner: scanner)
        manager.startEngine()
        #expect(await fake.settle(manager))
        #expect(manager.windows[id] != nil)
        #expect(manager.visible.contains(id))
    }
}
