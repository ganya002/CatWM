@testable import CatWM
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
