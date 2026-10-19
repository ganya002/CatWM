import AppKit
import SwiftUI

final class NumberEdit: ObservableObject {
    @Published var isEditing = false
    @Published var draft = ""
}
