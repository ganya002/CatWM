import AppKit
import SwiftUI

final class MenuModel: ObservableObject {
    @Published var items: [MenuItem] = []
    @Published var query = "" {
        didSet { if query.first?.isWhitespace == true { query = String(query.drop(while: \.isWhitespace)) } }
    }
    @Published var path: [String] = []
    @Published var highlight: [Int: String] = [:]
    @Published var appeared = false
    @Published var rowFrames: [String: CGRect] = [:]
    @Published var columnHeights: [Int: CGFloat] = [:]
    var opensLeft = true
    var close: () -> Void = {}
    var searchable = true
    var source: () -> [MenuItem] = MenuModel.build

    var openWork: DispatchWorkItem?
    var opening: String?
    var trimWork: DispatchWorkItem?
    var trimLevel = 0

    var results: [(item: MenuItem, crumb: String)] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var out: [(MenuItem, String)] = []
        func walk(_ list: [MenuItem], _ crumb: [String]) {
            for var i in list {
                switch i.kind {
                case .sub: walk(i.children, crumb + [i.label])
                case .action, .check, .radio, .footer, .attention:
                    let text = "\(i.label) \(i.keywords) \(crumb.joined(separator: " "))".lowercased()
                    guard i.enabled, words.allSatisfy({ text.contains($0) }) else { continue }
                    i.hidden = false
                    if i.kind == .footer || i.kind == .attention { i.kind = .action }
                    out.append((i, crumb.joined(separator: " › ")))
                default: break
                }
            }
        }
        walk(items, [])
        return out
    }

    var keyLevel: Int { query.isEmpty ? min(path.count, highlight.keys.filter { highlight[$0] != nil }.max() ?? 0) : 0 }
}

struct MenuItem: Identifiable {
    enum Kind {
        case action, check, radio, sub, label, separator, essentials, workspaces, layoutPicker, attention, footer
    }

    var id: String
    var kind: Kind = .action
    var label = ""
    var symbol: String?
    var image: NSImage?
    var shortcut: [String] = []
    var value: String?
    var checked = false
    var danger = false
    var enabled = true
    var hidden = false
    var keywords = ""
    var width: CGFloat = Theme.submenuWidth
    var children: [MenuItem] = []
    var keepOpen = false
    var rotates = false
    var badge: Int?
    var dot = false
    var action: (() -> Void)?

    var selectable: Bool {
        guard enabled, !hidden else { return false }
        return [.action, .check, .radio, .sub, .footer].contains(kind)
    }

    static func sep(_ id: String) -> MenuItem { MenuItem(id: id, kind: .separator) }
    static func label(_ id: String, _ text: String, shortcut: [String] = []) -> MenuItem {
        MenuItem(id: id, kind: .label, label: text, shortcut: shortcut)
    }
}

struct ShortcutIndex {
    private var mode: [String: [String]] = [:]
    private var global: [String: [String]] = [:]
    var modeName: String?
    var modeChord: [String] = []

    init() {
        let store = ConfigStore.shared
        let text = store.isScript
            ? store.settingsText : (try? String(contentsOf: Config.url, encoding: .utf8)) ?? defaultText
        let doc = ConfigDocument(text: text)
        let modeBind = doc.binds.first {
            $0.submap.isEmpty && $0.dispatcher == WindowActions.submap.name && $0.args.lowercased() != "reset"
        }
        if let modeBind {
            modeName = modeBind.args
            modeChord = doc.prettyShortcut(modeBind)
        }
        func table(_ submap: String) -> [String: [String]] {
            var out: [String: [String]] = [:]
            for action in doc.keyActions(in: submap) where out[action.title] == nil {
                out[action.title] = ConfigDocument.modifierCaps(action.flags) + [ConfigDocument.capLabel(action.key)]
            }
            return out
        }
        if let modeName { mode = table(modeName) }
        global = table("")
    }

    func keys(_ dispatcher: String, _ args: String = "") -> [String] {
        guard let title = Actions.all.first(where: { $0.dispatcher == dispatcher && $0.args == args })?.title else {
            return []
        }
        return mode[title] ?? global[title] ?? []
    }
}
