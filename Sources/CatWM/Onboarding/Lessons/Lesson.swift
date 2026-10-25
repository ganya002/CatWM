import AppKit
import SwiftUI

protocol Lesson: AnyObject {
    func prepare(_ coach: Coach)
    var count: Int { get }
    var startIndex: Int { get }
    var pausable: Bool { get }
    func step(_ i: Int, in coach: Coach) -> Coach.Step
    func ended(_ how: Coach.Ending, at index: Int)
}
