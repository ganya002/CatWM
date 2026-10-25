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
