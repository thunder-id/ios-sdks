// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderIDSwiftUI

enum ServerHealth: Equatable {
    case unknown
    case checking
    case healthy(Int)
    case unreachable(String)
}

/// Runs the capability checks and tracks their results and the server's health.
@MainActor
final class ChecksModel: ObservableObject {
    @Published private(set) var statuses: [CapabilityID: CheckStatus] = [:]
    @Published private(set) var isRunningAll = false
    @Published private(set) var health: ServerHealth = .unknown
    /// Drives the sheet that hosts the `SignIn` component for the app-native check.
    @Published var isNativeSignInPresented = false

    let config: PlaygroundConfig
    let storage: PlaygroundStorage
    let log: EventLog
    /// What the management checks found, for later checks and the explorer's live stories.
    let ids = ManagementIds()
    private weak var state: ThunderIDState?

    init(config: PlaygroundConfig, storage: PlaygroundStorage, log: EventLog) {
        self.config = config
        self.storage = storage
        self.log = log
        reset()
    }

    func bind(_ state: ThunderIDState) {
        self.state = state
    }

    var passCount: Int { statuses.values.filter(\.isPass).count }
    var total: Int { CapabilityCatalog.all.count }

    func status(_ id: CapabilityID) -> CheckStatus { statuses[id] ?? .idle(nil) }

    func reset() {
        for capability in CapabilityCatalog.all {
            switch capability.mode {
            case .unavailable(let reason): statuses[capability.id] = .unavailable(reason)
            case .interactive: statuses[capability.id] = .idle("Tap to run. Needs your input.")
            case .automatic: statuses[capability.id] = .idle(nil)
            }
        }
    }

    func run(_ capability: Capability) async {
        guard capability.isAvailable, let state else { return }
        if capability.id == .nativeSignIn {
            startNativeSignIn()
            return
        }
        guard let runner = CheckContext.runners[capability.id] else { return }
        statuses[capability.id] = .running
        let context = CheckContext(state: state, storage: storage, config: config, log: log, ids: ids)
        do {
            let reason = try await runner(context)
            statuses[capability.id] = .pass(reason)
            log.record("check:passed", capability.name, kind: .success)
        } catch {
            let reason = describe(error)
            statuses[capability.id] = .fail(reason)
            log.record("check:failed", "\(capability.name): \(reason)", kind: .error)
        }
    }

    /// Runs every automatic check in order. Interactive checks keep their last result.
    func runAll() async {
        guard !isRunningAll else { return }
        isRunningAll = true
        defer { isRunningAll = false }
        log.record("checks:runAll", "\(CapabilityCatalog.all.filter { $0.mode == .automatic }.count) checks")
        await checkHealth()
        for capability in CapabilityCatalog.all where capability.mode == .automatic {
            await run(capability)
        }
    }

    // MARK: - App-native sign-in

    private func startNativeSignIn() {
        guard config.applicationId != nil else {
            statuses[.nativeSignIn] = .fail("Set THUNDERID_APPLICATION_ID in Config.plist")
            return
        }
        statuses[.nativeSignIn] = .running
        log.record("signIn:started", "mode=app-native")
        isNativeSignInPresented = true
    }

    func finishNativeSignIn(error: String?) async {
        isNativeSignInPresented = false
        if let error {
            statuses[.nativeSignIn] = .fail(error)
            log.record("signIn:failed", error, kind: .error)
            return
        }
        await state?.refresh()
        let user = state?.user
        let who = user?.email ?? user?.username ?? user?.sub ?? "user"
        statuses[.nativeSignIn] = .pass("Signed in as \(who) through the flow execution API")
        log.record("signIn:completed", "mode=app-native", kind: .success)
    }

    func cancelNativeSignIn() {
        guard statuses[.nativeSignIn] == .running else { return }
        statuses[.nativeSignIn] = .idle("Cancelled")
        log.record("signIn:cancelled", "mode=app-native")
    }

    // MARK: - Server health

    func checkHealth() async {
        guard let url = URL(string: config.baseUrl + "/health/readiness") else {
            health = .unreachable("invalid base URL")
            return
        }
        health = .checking
        let started = Date()
        do {
            let (_, response) = try await HealthProbe.session.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            health = code == 200 ? .healthy(elapsed) : .unreachable("HTTP \(code)")
        } catch {
            health = .unreachable((error as? URLError)?.code == .cannotConnectToHost ? "offline" : "unreachable")
        }
        log.record("server:health", healthLabel, kind: health.isHealthy ? .success : .error)
    }

    var healthLabel: String {
        switch health {
        case .unknown: return "\(config.hostLabel) · not checked"
        case .checking: return "\(config.hostLabel) · checking"
        case .healthy(let millis): return "\(config.hostLabel) · healthy · \(millis) ms"
        case .unreachable(let reason): return "\(config.hostLabel) · \(reason)"
        }
    }
}

extension ServerHealth {
    var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }
}

/// URL session for the readiness probe. Like the SDK's own HTTP client, it accepts a self-signed
/// certificate only from a loopback host, which is how a local development server is reached.
private final class HealthProbe: NSObject, URLSessionDelegate {
    static let session = URLSession(configuration: .ephemeral, delegate: HealthProbe(), delegateQueue: nil)

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              ["localhost", "127.0.0.1", "::1"].contains(space.host),
              let trust = space.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
