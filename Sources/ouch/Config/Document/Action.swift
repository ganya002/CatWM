import AppKit
import Carbon
import Combine
import SwiftUI

struct Action: Identifiable {
    let title: String
    let category: ActionCategory
    let dispatcher: String
    let args: String
    let symbol: String
    var group: String? = nil
    var short: String? = nil
    var id: String { "\(dispatcher) \(args)" }
}
