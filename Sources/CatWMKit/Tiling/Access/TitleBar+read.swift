import ApplicationServices
import QuartzCore

extension TitleBar {
    package struct Node<Element> {
        package let element: Element
        package let role: String
        package let subrole: String?
        package let frame: CGRect
    }

    package static let budget = 150

    package static let lightSubroles: Set<String> = [
        kAXCloseButtonSubrole, kAXMinimizeButtonSubrole, kAXZoomButtonSubrole, kAXFullScreenButtonSubrole
    ]

    package static let controlRoles: Set<String> = [
        kAXButtonRole, kAXMenuButtonRole, kAXPopUpButtonRole, kAXCheckBoxRole, kAXRadioButtonRole,
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, kAXSliderRole, kAXIncrementorRole,
        kAXDisclosureTriangleRole, kAXColorWellRole, kAXListRole, kAXTableRole, kAXOutlineRole,
        kAXBrowserRole, kAXRowRole, "AXLink", "AXDateField"
    ]

    package static let deadline: CFTimeInterval = 0.1

    package static func read(_ window: AXUIElement) -> TitleBar? {
        dispatchPrecondition(condition: .notOnQueue(.main))
        let end = CACurrentMediaTime() + deadline
        guard case .value(let values) = window.values([kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute]),
              let bounds = rect(values[0], values[1]) else { return nil }
        return measure(window: bounds, children: values[2] as? [AXUIElement] ?? [], node: { element in
            CACurrentMediaTime() < end ? node(element) : .stalled
        }, children: children)
    }

    package static func measure<Element>(window: CGRect, children: [Element],
                                         node: (Element) -> AXRead<Node<Element>>,
                                         children expand: (Element) -> AXRead<[Element]>) -> TitleBar? {
        var search = TitleBarSearch<Element>()
        guard children.count <= budget, search.add(children, clip: window, read: node) else { return nil }
        let isLight = { (item: Reached<Element>) in item.node.subrole.map(lightSubroles.contains) ?? false }
        let lights = search.frontier.filter(isLight).map(\.visible).reduce(nil) { $0?.union($1) ?? $1 }
        search.frontier.removeAll(where: isLight)
        let contentTop = search.frontier.filter { $0.node.role != kAXStaticTextRole && !$0.visible.isEmpty }
            .map(\.visible.minY).min()
        let limit = window.minY + reach
        guard case .value(let controlTop) = search.topControl(below: limit, read: node, expand: expand) else {
            return nil
        }
        return TitleBar(lights: lights?.offsetBy(dx: -window.minX, dy: -window.minY),
                        contentTop: contentTop.map { $0 - window.minY },
                        controlTop: controlTop.map { $0 - window.minY })
    }

    private static func node(_ element: AXUIElement) -> AXRead<Node<AXUIElement>> {
        AXUIElementSetMessagingTimeout(element, axTimeout)
        let names = [kAXRoleAttribute, kAXSubroleAttribute, kAXPositionAttribute, kAXSizeAttribute]
        switch element.values(names) {
        case .stalled: return .stalled
        case .missing: return .missing
        case .value(let values):
            guard let role = values[0] as? String, let frame = rect(values[2], values[3]) else { return .missing }
            return .value(Node(element: element, role: role, subrole: values[1] as? String, frame: frame))
        }
    }

    private static func children(_ element: AXUIElement) -> AXRead<[AXUIElement]> {
        switch element.values([kAXChildrenAttribute]) {
        case .stalled: return .stalled
        case .missing: return .missing
        case .value(let values): return .value(values[0] as? [AXUIElement] ?? [])
        }
    }

    private static func rect(_ position: CFTypeRef?, _ size: CFTypeRef?) -> CGRect? {
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard let position, let size, CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent),
              [origin.x, origin.y, extent.width, extent.height].allSatisfy(\.isFinite) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}

private struct Reached<Element> {
    package let node: TitleBar.Node<Element>
    package let visible: CGRect
    package let clip: CGRect
}

private struct TitleBarSearch<Element> {
    package var frontier: [Reached<Element>] = []
    package var spent = 0

    package mutating func add(_ elements: [Element], clip: CGRect,
                              read: (Element) -> AXRead<TitleBar.Node<Element>>) -> Bool {
        for element in elements {
            spent += 1
            switch read(element) {
            case .stalled: return false
            case .missing: continue
            case .value(let found):
                let visible = found.frame.intersection(clip)
                if !visible.isNull { frontier.append(Reached(node: found, visible: visible, clip: clip)) }
            }
        }
        return true
    }

    package mutating func topControl(below limit: CGFloat, read: (Element) -> AXRead<TitleBar.Node<Element>>,
                                     expand: (Element) -> AXRead<[Element]>) -> AXRead<CGFloat?> {
        while let index = frontier.indices.min(by: { frontier[$0].visible.minY < frontier[$1].visible.minY }) {
            let item = frontier.remove(at: index)
            guard item.visible.minY < limit else { break }
            if TitleBar.controlRoles.contains(item.node.role), !item.visible.isEmpty {
                return .value(item.visible.minY)
            }
            guard spent < TitleBar.budget else { return .value(item.visible.minY) }
            spent += 1
            switch expand(item.node.element) {
            case .stalled: return .stalled
            case .missing: continue
            case .value(let inner):
                guard spent + inner.count <= TitleBar.budget else { return .value(item.visible.minY) }
                let clip = item.node.role == kAXScrollAreaRole ? item.visible : item.clip
                guard add(inner, clip: clip, read: read) else { return .stalled }
            }
        }
        return .value(nil)
    }
}

private extension AXUIElement {
    func values(_ names: [String]) -> AXRead<[CFTypeRef?]> {
        var raw: CFArray?
        let error = noted {
            AXUIElementCopyMultipleAttributeValues(self, names as CFArray, AXCopyMultipleAttributeOptions(), &raw)
        }
        if error == .cannotComplete { return .stalled }
        guard error == .success, let list = raw as? [CFTypeRef], list.count == names.count else { return .missing }
        var values: [CFTypeRef?] = []
        for value in list {
            guard CFGetTypeID(value) == AXValueGetTypeID(),
                  AXValueGetType(unsafeDowncast(value, to: AXValue.self)) == .axError else {
                values.append(value)
                continue
            }
            var failure = AXError.success
            AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .axError, &failure)
            if failure == .cannotComplete { return .stalled }
            values.append(nil)
        }
        return .value(values)
    }
}
