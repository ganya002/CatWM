import CoreGraphics

struct ColorFillSizing {
    let source: CGRect
    let target: CGRect

    var releasesSpace: Bool { target.width < source.width || target.height < source.height }

    func request(predicted: CGRect, viewport: CGRect) -> CGRect {
        let bounds = CGRect(x: ceil(viewport.minX), y: ceil(viewport.minY),
                            width: floor(viewport.maxX) - ceil(viewport.minX),
                            height: floor(viewport.maxY) - ceil(viewport.minY))
        guard bounds.width >= 1, bounds.height >= 1 else { return viewport.pixelAligned }
        let size = CGSize(width: max(1, floor(min(predicted.width, bounds.width))),
                          height: max(1, floor(min(predicted.height, bounds.height))))
        return CGRect(x: min(max(predicted.minX.rounded(), bounds.minX), bounds.maxX - size.width),
                      y: min(max(predicted.minY.rounded(), bounds.minY), bounds.maxY - size.height),
                      width: size.width, height: size.height)
    }
}
