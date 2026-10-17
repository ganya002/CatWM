import AppKit
import SwiftUI

struct WorkspaceStrip: View {
    let names: [String]
    let current: String?
    let occupied: Set<String>
    let pick: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(names, id: \.self) { n in WorkspacePill(name: n, current: n == current, occupied: occupied.contains(n)) { pick(n) } }
        }
    }
}
