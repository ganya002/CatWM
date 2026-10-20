import AppKit

struct Release {
    struct Feature {
        let id: String
        let symbol: String
        let title: String
        let text: String
        var action: (label: String, run: () -> Void)?
        var tour: ((Coach) -> [PlannedStep])?
    }

    let version: String
    let features: [Feature]
}
