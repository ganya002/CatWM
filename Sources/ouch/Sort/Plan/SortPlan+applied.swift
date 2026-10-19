import AppKit

extension SortPlan {
    var applied: SortApply {
        SortApply(display: display,
                  lanes: lanes.map {
                      SortApplyLane(name: $0.workspace, label: $0.name.trimmingCharacters(in: .whitespaces),
                                    layout: $0.layout, ids: $0.ids)
                  },
                  close: close, dropped: Array(claimed.union(existing)))
    }
}
