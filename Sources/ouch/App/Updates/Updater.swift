import Foundation
import Sparkle

final class Updater: NSObject, SPUUpdaterDelegate, ObservableObject {
    static let shared = Updater()

    private static let betaKey = "receiveBetaUpdates"

    private var controller: SPUStandardUpdaterController?

    let isConfigured: Bool = {
        let info = Bundle.main.infoDictionary ?? [:]
        let url = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        return url.hasPrefix("https://") && !key.isEmpty && !key.hasPrefix("REPLACE")
    }()

    @Published var lastChecked: Date?

    func start() {
        guard isConfigured, controller == nil else { return }
        let channel = Bundle.main.infoDictionary?["OuchUpdateChannel"] as? String
        UserDefaults.standard.register(defaults: [Self.betaKey: channel == "beta"])
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

    var receivesBeta: Bool {
        get { UserDefaults.standard.bool(forKey: Self.betaKey) }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: Self.betaKey) }
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        receivesBeta ? ["beta"] : []
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        DispatchQueue.main.async { self.lastChecked = updater.lastUpdateCheckDate }
    }
}
