import AppKit
import SwiftUI

final class NumberEdit: ObservableObject {
    @Published var on = false
    @Published var draft = ""
}
