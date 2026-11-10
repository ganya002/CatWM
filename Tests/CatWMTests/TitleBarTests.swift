import ApplicationServices
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct TitleBarKindTests {
    let lights = CGRect(x: 8, y: 8, width: 62, height: 16)

    @Test func noLightsIsNone() {
        let bar = TitleBar(lights: nil, contentTop: nil, controlTop: nil)
        #expect(bar.kind == .none)
        #expect(bar.clearTop == nil)
    }

    @Test func controlOnTheLightRowIsUnified() {
        let bar = TitleBar(lights: lights, contentTop: 0, controlTop: 3)
        #expect(bar.kind == .unifiedToolbar)
        #expect(bar.clearTop == 3)
    }

    @Test func contentBelowTheLightsIsStandard() {
        let bar = TitleBar(lights: lights, contentTop: 32, controlTop: 32)
        #expect(bar.kind == .standard)
        #expect(bar.clearTop == 32)
    }

    @Test func toolbarBelowTheTitleRowIsStandard() {
        let bar = TitleBar(lights: lights, contentTop: 28, controlTop: 36)
        #expect(bar.kind == .standard)
        #expect(bar.clearTop == 36)
    }

    @Test func standardWithNoControlIsClearToTheReach() {
        let bar = TitleBar(lights: lights, contentTop: 32, controlTop: nil)
        #expect(bar.clearTop == TitleBar.reach)
    }

    @Test func contentUnderTheLightsIsFullSizeAndUnknown() {
        let bar = TitleBar(lights: lights, contentTop: 0, controlTop: nil)
        #expect(bar.kind == .fullSizeContent)
        #expect(bar.clearTop == nil)
    }

    @Test func noContentIsFullSize() {
        #expect(TitleBar(lights: lights, contentTop: nil, controlTop: nil).kind == .fullSizeContent)
    }
}

@Suite struct TitleBarMeasureTests {
    typealias Node = TitleBar.Node<Int>

    let window = CGRect(x: 100, y: 50, width: 800, height: 600)

    func at(_ id: Int, _ role: String, _ frame: CGRect, subrole: String? = nil) -> Node {
        Node(element: id, role: role, subrole: subrole,
             frame: frame.offsetBy(dx: window.minX, dy: window.minY))
    }

    func lights() -> [Node] {
        [at(1, kAXButtonRole, CGRect(x: 8, y: 8, width: 16, height: 16), subrole: kAXCloseButtonSubrole),
         at(2, kAXButtonRole, CGRect(x: 31, y: 8, width: 16, height: 16), subrole: kAXMinimizeButtonSubrole),
         at(3, kAXButtonRole, CGRect(x: 54, y: 8, width: 16, height: 16), subrole: kAXFullScreenButtonSubrole)]
    }

    func measure(_ nodes: [Node], tree: [Int: [Int]], stalls: Set<Int> = []) -> (TitleBar?, Int) {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.element, $0) })
        var expanded = 0
        let bar = TitleBar.measure(window: window, children: tree[0] ?? [], node: { id in
            stalls.contains(id) ? .stalled : byID[id].map { .value($0) } ?? .missing
        }, children: { id in
            expanded += 1
            return .value(tree[id] ?? [])
        })
        return (bar, expanded)
    }

    @Test func lightsDoNotCountAsControls() throws {
        let text = at(4, kAXTextAreaRole, CGRect(x: 0, y: 32, width: 800, height: 568))
        let (bar, _) = measure(lights() + [text], tree: [0: [1, 2, 3, 4]])
        let found = try #require(bar)
        #expect(found.kind == .standard)
        #expect(found.clearTop == 32)
        #expect(found.lights == CGRect(x: 8, y: 8, width: 62, height: 16))
    }

    @Test func findsTheTopControlDeepInTheTree() throws {
        let nodes = lights() + [
            at(4, kAXGroupRole, CGRect(x: 0, y: 0, width: 800, height: 600)),
            at(5, kAXToolbarRole, CGRect(x: 74, y: 0, width: 726, height: 34)),
            at(6, kAXButtonRole, CGRect(x: 111, y: 3, width: 28, height: 28)),
            at(7, kAXGroupRole, CGRect(x: 0, y: 65, width: 800, height: 535))
        ]
        let tree = [0: [1, 2, 3, 4], 4: [7, 5], 5: [6], 7: [8, 9, 10]]
        let (bar, expanded) = measure(nodes, tree: tree)
        let found = try #require(bar)
        #expect(found.kind == .unifiedToolbar)
        #expect(found.clearTop == 3)
        #expect(expanded == 2)
    }

    @Test func scrolledOutRowsDoNotCount() {
        let nodes = lights() + [
            at(4, kAXScrollAreaRole, CGRect(x: 0, y: 40, width: 800, height: 560)),
            at(5, kAXRowRole, CGRect(x: 0, y: -200, width: 800, height: 20)),
            at(6, kAXRowRole, CGRect(x: 0, y: 44, width: 800, height: 20))
        ]
        let (bar, _) = measure(nodes, tree: [0: [1, 2, 3, 4], 4: [5, 6]])
        #expect(bar?.clearTop == 44)
    }

    @Test func emptyContentUnderTheLightsIsUnknown() throws {
        let nodes = lights() + [at(4, kAXGroupRole, CGRect(x: 0, y: 0, width: 800, height: 600))]
        let (bar, _) = measure(nodes, tree: [0: [1, 2, 3, 4]])
        let found = try #require(bar)
        #expect(found.kind == .fullSizeContent)
        #expect(found.clearTop == nil)
    }

    @Test func aStallGivesNoAnswer() {
        let nodes = lights() + [at(4, kAXGroupRole, CGRect(x: 0, y: 0, width: 800, height: 600))]
        let (bar, _) = measure(nodes, tree: [0: [1, 2, 3, 4], 4: [5]], stalls: [5])
        #expect(bar == nil)
    }

    @Test func aWideNodeStopsAtItsTop() {
        let rows = Array(1_000..<1_000 + TitleBar.budget)
        let nodes = lights() + [at(4, kAXGroupRole, CGRect(x: 0, y: 20, width: 800, height: 580))]
        let (bar, expanded) = measure(nodes, tree: [0: [1, 2, 3, 4], 4: rows])
        #expect(bar?.clearTop == 20)
        #expect(expanded == 1)
    }

    @Test func controlsBelowTheReachAreIgnored() {
        let nodes = lights() + [
            at(4, kAXGroupRole, CGRect(x: 0, y: 32, width: 800, height: 568)),
            at(5, kAXButtonRole, CGRect(x: 0, y: 200, width: 80, height: 20))
        ]
        let (bar, _) = measure(nodes, tree: [0: [1, 2, 3, 4], 4: [5]])
        #expect(bar?.clearTop == TitleBar.reach)
    }
}
