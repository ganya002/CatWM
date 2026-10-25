import Foundation

struct RestoreTarget: Equatable {
    var id: UUID
    var bundleID: String
    var appName: String
    var document: String?
}

struct AppLaunchState: Equatable {
    var running: Bool
    var finishedLaunching: Bool
    var openable: Bool
}

struct RestoreRequest: Equatable {
    var savedID: UUID
    var bundleID: String
    var appName: String
    var document: String?
    var token: UUID
}

struct RestoreScheduler {
    static let totalWait: TimeInterval = 15
    static let pollInterval: TimeInterval = 0.3
    static let requestGap: TimeInterval = 0.3
    static let launchSettle: TimeInterval = 0.75
    static let firstWindowWait: TimeInterval = 3
    static let retryDelay: TimeInterval = 0.5
    static let maxAttempts = 3

    struct Step: Equatable {
        var launch: [String]
        var requests: [RestoreRequest]
        var keepWaiting: Bool
    }

    private enum AttemptOutcome {
        case pending
        case refused
        case failed
    }

    private struct Attempt {
        var outcome: AttemptOutcome
        var time: Date
        var tries: Int
        var token: UUID
    }

    private enum Kind {
        case warm
        case cold
    }

    private enum Phase {
        case launch
        case wait
        case ready
        case giveUp(String)
    }

    private var attempts: [UUID: Attempt] = [:]
    private var kinds: [String: Kind] = [:]
    private var readyAt: [String: Date] = [:]
    private var launched: Set<String> = []
    private var launchFailed: Set<String> = []
    private var lastRequest: [String: Date] = [:]
    private var settledMatches: [String: Set<UUID>] = [:]
    private(set) var cancelled = false
    private(set) var failures = Set<String>()

    init() {}

    mutating func cancel() {
        cancelled = true
    }

    mutating func noteRefused(_ savedID: UUID, appName: String, now: Date) {
        guard !cancelled, var attempt = attempts[savedID], attempt.outcome == .pending else { return }
        attempt.outcome = .refused
        attempt.time = now
        attempts[savedID] = attempt
        if attempt.tries >= Self.maxAttempts { failures.insert(appName) }
    }

    mutating func noteFailed(_ savedID: UUID, token: UUID, appName: String, now: Date) {
        guard !cancelled, var attempt = attempts[savedID], attempt.token == token,
              attempt.outcome == .pending else { return }
        attempt.outcome = .failed
        attempt.time = now
        attempts[savedID] = attempt
        if attempt.tries >= Self.maxAttempts { failures.insert(appName) }
    }

    mutating func noteLaunchFailed(_ bundleID: String, appName: String) {
        guard !cancelled else { return }
        launchFailed.insert(bundleID)
        failures.insert(appName)
    }

    mutating func step(now: Date, deadline: Date, targets: [RestoreTarget], matched: Set<UUID>,
                       apps: [String: AppLaunchState]) -> Step {
        if cancelled || now >= deadline { return Step(launch: [], requests: [], keepWaiting: false) }
        let pending = targets.filter { !matched.contains($0.id) }
        if pending.isEmpty { return Step(launch: [], requests: [], keepWaiting: false) }
        var launch: [String] = []
        var requests: [RestoreRequest] = []
        var keep = false
        for bundle in Set(pending.map(\.bundleID)).sorted() {
            let group = pending.filter { $0.bundleID == bundle }
            guard let appName = group.first?.appName else { continue }
            let app = apps[bundle] ?? AppLaunchState(running: false, finishedLaunching: false, openable: false)
            let appMatches = Set(targets.filter { $0.bundleID == bundle && matched.contains($0.id) }.map(\.id))
            if kinds[bundle] == .cold, lastRequest[bundle] == nil, readyAt[bundle] != nil,
               settledMatches[bundle] != appMatches {
                readyAt[bundle] = now
            }
            settledMatches[bundle] = appMatches
            switch phase(bundle, app: app, appName: appName, now: now,
                         awaitingFirstWindow: appMatches.isEmpty && group.allSatisfy({ $0.document == nil })) {
            case .launch:
                launch.append(bundle)
                keep = true
            case .wait:
                keep = true
            case .giveUp(let name):
                failures.insert(name)
            case .ready:
                let admitted = admit(group, now: now, deadline: deadline)
                if admitted.isEmpty {
                    if group.contains(where: { stillWorking($0.id) }) { keep = true }
                    continue
                }
                for target in admitted {
                    let token = UUID()
                    let tries = (attempts[target.id]?.tries ?? 0) + 1
                    attempts[target.id] = Attempt(outcome: .pending, time: now, tries: tries, token: token)
                    requests.append(RestoreRequest(savedID: target.id, bundleID: target.bundleID,
                                                           appName: target.appName, document: target.document,
                                                           token: token))
                }
                lastRequest[bundle] = now
                keep = true
            }
        }
        return Step(launch: launch, requests: requests, keepWaiting: keep)
    }

    private mutating func phase(_ bundle: String, app: AppLaunchState, appName: String, now: Date,
                                awaitingFirstWindow: Bool) -> Phase {
        if !app.running {
            if launchFailed.contains(bundle) || !app.openable { return .giveUp(appName) }
            kinds[bundle] = .cold
            if launched.contains(bundle) { return .wait }
            launched.insert(bundle)
            return .launch
        }
        if kinds[bundle] == nil {
            kinds[bundle] = app.finishedLaunching ? .warm : .cold
        }
        switch kinds[bundle] ?? .cold {
        case .warm:
            return app.finishedLaunching ? .ready : .wait
        case .cold:
            guard app.finishedLaunching else { return .wait }
            if readyAt[bundle] == nil { readyAt[bundle] = now }
            let settle = awaitingFirstWindow && lastRequest[bundle] == nil ? Self.firstWindowWait : Self.launchSettle
            guard let ready = readyAt[bundle], now.timeIntervalSince(ready) + 0.001 >= settle else { return .wait }
            return .ready
        }
    }

    private func admit(_ group: [RestoreTarget], now: Date, deadline: Date) -> [RestoreTarget] {
        let fresh = group.filter { attempts[$0.id] == nil }
        let retries = group.filter { canRetry($0.id, now: now) }
        let slots = max(1, Int(deadline.timeIntervalSince(now) / Self.requestGap))
        if fresh.count > slots { return fresh }
        if let bundle = group.first?.bundleID, let last = lastRequest[bundle],
           now.timeIntervalSince(last) + 0.001 < Self.requestGap {
            return []
        }
        if let next = fresh.first ?? retries.first { return [next] }
        return []
    }

    private func canRetry(_ id: UUID, now: Date) -> Bool {
        guard let attempt = attempts[id] else { return false }
        switch attempt.outcome {
        case .pending:
            return false
        case .refused, .failed:
            return attempt.tries < Self.maxAttempts && now.timeIntervalSince(attempt.time) + 0.001 >= Self.retryDelay
        }
    }

    private func stillWorking(_ id: UUID) -> Bool {
        guard let attempt = attempts[id] else { return true }
        switch attempt.outcome {
        case .pending:
            return true
        case .refused, .failed:
            return attempt.tries < Self.maxAttempts
        }
    }
}

enum NewWindowCommand {
    static func isPlainCommandN(command: String?, modifiers: Int?) -> Bool {
        command?.lowercased() == "n" && modifiers == 0
    }
}
