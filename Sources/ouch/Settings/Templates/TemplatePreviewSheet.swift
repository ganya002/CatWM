import SwiftUI

struct TemplatePreviewSheet: View {
    let template: WorkspaceTemplate
    let close: () -> Void

    private var width: CGFloat {
        min(Theme.menuWidth * 4, (NSScreen.main?.visibleFrame.width ?? 1200) - Theme.Space.xxl * 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack {
                Text(template.name).textStyle(.title).oneLine()
                Spacer()
                OButton("Close", variant: .ghost, action: close).keyboardShortcut(.cancelAction)
            }
            if let data = template.screenshot, let image = NSImage(data: data) {
                let imageWidth = width - Theme.Space.xl * 2
                let imageHeight = imageWidth * image.size.height / max(image.size.width, 1)
                ScrollView {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: imageWidth, height: imageHeight)
                        .accessibilityLabel("Saved screenshot of \(template.name)")
                }
                .frame(height: min(imageHeight, (NSScreen.main?.visibleFrame.height ?? 800) - Theme.Space.xxl * 5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
            Text(template.summary).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
        }
        .padding(Theme.Space.xl)
        .frame(width: width)
        .foregroundStyle(Theme.ink)
        .background(Theme.surfaceRaised)
    }
}
