import Foundation
import Sparkle

/// In-app updates through Sparkle, with releases hosted by Amore (https://amore.computer).
/// Inert until Info.plist has the SUFeedURL and SUPublicEDKey that `amore setup` prints, so a
/// fresh checkout never shows Sparkle's "feed missing" alert.
final class Updater: NSObject, SPUUpdaterDelegate, ObservableObject {
    static let shared = Updater()

    private static let betaKey = "receiveBetaUpdates"

    private var controller: SPUStandardUpdaterController?

    /// False until the feed and key are filled in.
    let isConfigured: Bool = {
        let info = Bundle.main.infoDictionary ?? [:]
        let url = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        return url.hasPrefix("https://") && !key.isEmpty && !key.hasPrefix("REPLACE")
    }()

    @Published var lastChecked: Date?

    func start() {
        guard isConfigured, controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        lastChecked = controller?.updater.lastUpdateCheckDate
    }

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
        lastChecked = controller?.updater.lastUpdateCheckDate
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { objectWillChange.send(); controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloads: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { objectWillChange.send(); controller?.updater.automaticallyDownloadsUpdates = newValue }
    }

    /// Opt in to releases published to Amore's "beta" channel (`amore release --channel beta`).
    var receivesBeta: Bool {
        get { UserDefaults.standard.bool(forKey: Self.betaKey) }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: Self.betaKey) }
    }

    // MARK: SPUUpdaterDelegate

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        receivesBeta ? ["beta"] : []
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        DispatchQueue.main.async { self.lastChecked = updater.lastUpdateCheckDate }
    }
}
