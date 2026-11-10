import AppKit
import CatWMKit
import SwiftUI

final class WhatsNew {
    static let shared = WhatsNew()
    static let seenKey = "whatsNew.seen"
    static let launchDelay: TimeInterval = 4
    static let retryDelay: TimeInterval = 30

    private let defaults: UserDefaults
    let releases: [Release]
    let model = WhatsNewModel()
    var panel: CatWMPanel?

    init(defaults: UserDefaults = Instance.defaults, releases: [Release] = Release.all) {
        self.defaults = defaults
        self.releases = releases
    }

    var isOpen: Bool { panel != nil }

    var seen: Set<String> { Set(defaults.stringArray(forKey: Self.seenKey) ?? []) }

    var unseen: [(version: String, feature: Release.Feature)] {
        let seen = seen
        return releases.flatMap { release in
            release.features.filter { !seen.contains($0.id) }.map { (release.version, $0) }
        }
    }

    var hasNews: Bool { !unseen.isEmpty }

    func adoptBaseline(onboarded: Bool) {
        guard defaults.object(forKey: Self.seenKey) == nil, !onboarded else { return }
        markSeen(releases.flatMap(\.features))
    }

    func markSeen(_ features: [Release.Feature]) {
        defaults.set(Array(seen.union(features.map(\.id))), forKey: Self.seenKey)
    }

    func launched() {
        adoptBaseline(onboarded: Onboarding.isDone)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchDelay) { [weak self] in self?.offer() }
    }

    func offer(attempts: Int = 10) {
        guard hasNews, Onboarding.isDone, !isOpen else { return }
        let busy = Onboarding.shared.isRunning || SortPanel.shared.isOpen || !WindowManager.shared.isStarted
            || !Hotkeys.shared.submap.isEmpty
        guard busy else { return show(takeFocus: false) }
        guard attempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
            self?.offer(attempts: attempts - 1)
        }
    }
}
