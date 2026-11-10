@testable import CatWM
@testable import CatWMKit
import Testing

@Test @MainActor func settingsSearchAcceptsWhitespaceBetweenWords() {
    let doc = ConfigDocument(text: "")
    let expected = SettingsIndex.search("window gap", doc: doc).map(\.id)
    #expect(!expected.isEmpty)
    #expect(SettingsIndex.search("window\tgap", doc: doc).map(\.id) == expected)
    #expect(SettingsIndex.search("window\ngap", doc: doc).map(\.id) == expected)
}

@Test @MainActor func settingsSearchFindsConfigOptionName() {
    let doc = ConfigDocument(text: "")
    #expect(SettingsIndex.search("mouse-swaps-windows", doc: doc).contains { $0.id == "windows.dragSwap" })
}

@Test @MainActor func settingsSearchFindsAcceptedConfigAliases() {
    let doc = ConfigDocument(text: "")
    for (name, id) in [
        ("smart-gaps", "layout.smartGaps"),
        ("follow_mouse", "windows.ffm"),
        ("new_is_master", "windows.newMain"),
        ("dim_inactive", "windows.dimOthers")
    ] {
        #expect(ConfigOption.named(name)?.setting?.id == id)
        let matches = SettingsIndex.search(name, doc: doc).filter { $0.id == id }
        #expect(matches.count == 1, "Search must find the setting configured by \(name)")
    }
}
