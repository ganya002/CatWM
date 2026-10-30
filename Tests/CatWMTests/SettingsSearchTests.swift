@testable import CatWM
import Testing

@Test @MainActor func settingsSearchAcceptsWhitespaceBetweenWords() {
    let doc = ConfigDocument(text: "")
    let expected = SettingsIndex.search("window gap", doc: doc).map(\.id)
    #expect(!expected.isEmpty)
    #expect(SettingsIndex.search("window\tgap", doc: doc).map(\.id) == expected)
    #expect(SettingsIndex.search("window\ngap", doc: doc).map(\.id) == expected)
}
