@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@Test @MainActor func aStalledAppHoldsTheRestoreOnlyWhileItHasUnmatchedWindows() {
    let editor = RestoreTarget(id: UUID(), bundleID: "com.example.editor", appName: "Editor", document: nil)
    let other = RestoreTarget(id: UUID(), bundleID: "com.example.other", appName: "Other", document: nil)
    let all = [editor, other]
    #expect(TemplateRestorer.waitsOnStall(all, matched: [other.id], stalled: [editor.bundleID]))
    #expect(!TemplateRestorer.waitsOnStall(all, matched: [editor.id], stalled: [editor.bundleID]))
    #expect(!TemplateRestorer.waitsOnStall(all, matched: [], stalled: []))
}
