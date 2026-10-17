import AppKit

enum TemplateWindowKind {
    static func includes(subrole: String?, minimized: Bool) -> Bool {
        subrole == kAXStandardWindowSubrole || (minimized && subrole == kAXDialogSubrole)
    }
}
