import AppKit
import SwiftUI

struct WorkspaceStrip: View {
    let names: [String]
    let current: String?
    let occupied: Set<String>
    let pick: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(names, id: \.self) { name in
                WorkspacePill(name: name, current: name == current, occupied: occupied.contains(name)) { pick(name) }
            }
        }
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var workspaceExample: some View {
        WorkspaceStrip(names: (1...9).map(String.init), current: model.workspace,
                       occupied: ["1", "2", "3", "5"]) { model.workspace = $0 }
    }
}
#endif
