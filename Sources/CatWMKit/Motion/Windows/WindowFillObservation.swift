import CoreGraphics

package struct WindowFillObservation {
    package let participants: Set<CGWindowID>
    package let order: [CGWindowID]
    package let frames: [CGWindowID: CGRect]

    package func canPresent(_ regions: [CGRect], excluding: Set<CGWindowID>) -> Bool {
        WindowSceneCapture.unobscured(regions, participants: participants, excluding: excluding,
                                     order: order, frame: { frames[$0] })
    }

    package func cutout(for id: CGWindowID, requested: CGRect) -> CGRect? {
        guard let observed = frames[id], !observed.isNull else { return nil }
        return requested.isNull ? observed : observed.union(requested)
    }
}
