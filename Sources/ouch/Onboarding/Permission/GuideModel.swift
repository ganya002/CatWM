import AppKit
import SwiftUI

final class GuideModel: ObservableObject {
    @Published var granted = false
    @Published var kind = Permission.accessibility
    @Published var alertUp = false
}
