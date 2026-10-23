import AppKit
import SwiftUI

enum SortZone: Hashable {
    case lane(UUID), add, close, display(String), row(CGWindowID), tabs(CGWindowID), scroller
}
