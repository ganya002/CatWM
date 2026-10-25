import AppKit
import SwiftUI

enum SortZone: Hashable {
    case lane(UUID), add, close, panel, display(String), row(CGWindowID), tabs(CGWindowID), scroller
}
