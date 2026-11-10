import AppKit

package struct WorkspaceTemplate: Codable, Identifiable {
    package var id = UUID()
    package var name: String
    package var createdAt = Date()
    package var tilingEnabled: Bool
    package var displays: [Display]
    package var windows: [SavedWindow]
    package var screenshot: Data?

    package init(name: String, tilingEnabled: Bool, displays: [Display], windows: [SavedWindow]) {
        self.name = name
        self.tilingEnabled = tilingEnabled
        self.displays = displays
        self.windows = windows
    }

    package struct Display: Codable, Identifiable {
        package var id: String
        package var name: String
        package var frame: CGRect
        package var visible: CGRect
        package var isMain: Bool
        package var layout: String
        package var ratio: CGFloat
        package var mainCount: Int
    }

    package var summary: String {
        "\(windows.count) \(windows.count == 1 ? "window" : "windows") · "
            + "\(displays.count) \(displays.count == 1 ? "display" : "displays")"
    }

    package static func restoredFrame(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0, destination.width > 0, destination.height > 0,
              [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) else { return destination }
        let width = min(destination.width, max(1, frame.width * destination.width / source.width))
        let height = min(destination.height, max(1, frame.height * destination.height / source.height))
        let x = destination.minX + (frame.minX - source.minX) * destination.width / source.width
        let y = destination.minY + (frame.minY - source.minY) * destination.height / source.height
        return CGRect(x: min(max(x, destination.minX), destination.maxX - width),
                      y: min(max(y, destination.minY), destination.maxY - height), width: width, height: height)
    }

    package func displayMap(available: [(id: String, isMain: Bool)]) -> [String: String] {
        guard let fallback = available.first(where: \.isMain) ?? available.first else { return [:] }
        var result: [String: String] = [:]
        var used = Set<String>()
        for display in displays where available.contains(where: { $0.id == display.id }) {
            result[display.id] = display.id
            used.insert(display.id)
        }
        for display in displays where result[display.id] == nil {
            let target = available.first { !used.contains($0.id) && $0.isMain == display.isMain }
                ?? available.first { !used.contains($0.id) }
                ?? fallback
            result[display.id] = target.id
            used.insert(target.id)
        }
        return result
    }
}
