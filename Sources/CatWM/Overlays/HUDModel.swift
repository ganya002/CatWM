import AppKit
import SwiftUI

final class HUDModel: ObservableObject {
    @Published var text = ""
    @Published var layout: Layout?
    @Published var warning = false
    @Published var pops = 0
}
