import AppKit

extension SortPlan {
    var applied: SortApply {
        SortApply(display: display, lanes: lanes.map { ($0.ws, $0.name.trimmingCharacters(in: .whitespaces), $0.layout, $0.ids) },
                  close: close, dropped: Array(claimed.union(existing)))
    }
}
