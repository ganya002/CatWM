@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@Suite struct WhatsNewTests {
    private let releases = [
        Release(version: "0.4", features: [
            .init(id: "0.4.a", symbol: "sparkles", title: "A", text: "")
        ]),
        Release(version: "0.3", features: [
            .init(id: "0.3.a", symbol: "sparkles", title: "B", text: ""),
            .init(id: "0.3.b", symbol: "sparkles", title: "C", text: "")
        ])
    ]

    private func fresh() -> UserDefaults {
        let name = "whatsnew.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func newUserStartsCaughtUp() {
        let news = WhatsNew(defaults: fresh(), releases: releases)
        news.adoptBaseline(onboarded: false)
        #expect(!news.hasNews)
    }

    @Test func existingUserSeesEveryFeature() {
        let news = WhatsNew(defaults: fresh(), releases: releases)
        news.adoptBaseline(onboarded: true)
        #expect(news.unseen.map(\.feature.id) == ["0.4.a", "0.3.a", "0.3.b"])
        #expect(news.unseen.map(\.version) == ["0.4", "0.3", "0.3"])
    }

    @Test func laterReleasesShowAfterTheBaseline() {
        let defaults = fresh()
        WhatsNew(defaults: defaults, releases: Array(releases.dropFirst())).adoptBaseline(onboarded: false)
        let news = WhatsNew(defaults: defaults, releases: releases)
        news.adoptBaseline(onboarded: true)
        #expect(news.unseen.map(\.feature.id) == ["0.4.a"])
    }

    @Test func markSeenClearsOnlyThoseFeatures() {
        let news = WhatsNew(defaults: fresh(), releases: releases)
        news.markSeen(releases[1].features)
        #expect(news.unseen.map(\.feature.id) == ["0.4.a"])
    }

    @Test func catalogIDsAreUnique() {
        let ids = Release.all.flatMap(\.features).map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
