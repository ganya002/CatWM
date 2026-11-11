import CatWMKit
import SwiftUI

struct LabPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            Text("Features still in testing. They can change, slow CatWM down or go away.")
                .textStyle(.caption).foregroundStyle(Theme.inkMuted)
            OGroup("Experiments") {
                OptionRows(pane: .lab, section: "Experiments", doc: doc, settingsUI: settingsUI)
                if doc.config.resizeAnimation != .live && !Permission.screenRecording.isGranted {
                    ORow("Waiting for Screen Recording", description: "Windows resize live until you allow it",
                         symbol: "exclamationmark.triangle.fill") {
                        OButton("Allow…", size: .small) { Permission.screenRecording.request() }
                    }
                }
            }
            AdditionalOptionGroups(pane: .lab, doc: doc, settingsUI: settingsUI)
        }
    }
}
