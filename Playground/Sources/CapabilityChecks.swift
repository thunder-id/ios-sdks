// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderIDSwiftUI

/// A check that did not pass, with the reason shown under its row.
struct CheckFailure: Error {
    let reason: String

    init(_ reason: String) { self.reason = reason }
}

func describe(_ error: Error) -> String {
    if let failure = error as? CheckFailure { return failure.reason }
    if let sdkError = error as? ThunderIDError { return "[\(sdkError.code.rawValue)] \(sdkError.message)" }
    return error.localizedDescription
}

/// Everything a check needs. Each check calls the real SDK and returns the reason it passed, or
/// throws the reason it failed.
@MainActor
struct CheckContext {
    let state: ThunderIDState
    let storage: PlaygroundStorage
    let config: PlaygroundConfig
    let log: EventLog
    let ids: ManagementIds

    var client: ThunderIDClient { state.client }

    typealias Runner = @MainActor (CheckContext) async throws -> String

    static let runners: [CapabilityID: Runner] = authRunners.merging(managementRunners) { current, _ in current }

    private static let authRunners: [CapabilityID: Runner] = [
        .browserSignIn: { try await $0.signInWithBrowser() },
        .passkey: { try await $0.passkey() },
        .signOut: { try await $0.signOut() },
        .redirectCallback: { try await $0.redirectCallback() },
        .tokenRefresh: { try await $0.tokenRefresh() },
        .secureStorage: { try await $0.secureStorage() },
        .userInfo: { try await $0.userInfo() },
        .translations: { try $0.translations() }
    ]

    func requireApplicationId() throws -> String {
        guard let applicationId = config.applicationId else {
            throw CheckFailure("Set THUNDERID_APPLICATION_ID in Config.plist")
        }
        return applicationId
    }

    func requireSignedIn() async throws {
        guard (try? await client.isSignedIn()) == true else {
            throw CheckFailure("Not signed in. Run a sign-in check first.")
        }
    }

    // MARK: - Authentication

    func signInWithBrowser() async throws -> String {
        guard config.clientId != nil, let scheme = config.callbackScheme else {
            throw CheckFailure("Set THUNDERID_CLIENT_ID and THUNDERID_AFTER_SIGN_IN_URL in Config.plist")
        }
        let url = try client.buildSignInURL()
        log.record("signIn:started", "mode=system-browser")
        let callback: URL
        do {
            callback = try await FederatedAuthSession().authenticate(url: url, callbackURLScheme: scheme)
        } catch is FederatedAuthSession.CancelledError {
            throw CheckFailure("Cancelled in the browser")
        }
        log.record("callback:received", "\(scheme)://\(callback.host ?? "")?code=…")
        let user = try await client.handleRedirectCallback(url: callback)
        await state.refresh()
        log.record("signIn:completed", "sub=\(user.sub ?? "?")", kind: .success)
        return "Signed in as \(user.email ?? user.username ?? user.sub ?? "user")"
    }

    /// Starts an authentication flow and looks for a passkey step. The ceremony itself runs inside
    /// `SignIn`, which hands the server's challenge to `PasskeyAuthSession`.
    func passkey() async throws -> String {
        let applicationId = try requireApplicationId()
        let response = try await client.signIn(
            payload: EmbeddedSignInPayload(),
            request: EmbeddedFlowRequestConfig(applicationId: applicationId)
        )
        log.record("flow:initiated", "step=\(response.stepId ?? "?")")
        if response.flowStatus == .error {
            throw CheckFailure(response.failureReason ?? "The flow returned an error")
        }
        guard FlowInspector.mentionsPasskey(response) else {
            throw CheckFailure("The first sign-in step offers no passkey option. Add one to the app's flow.")
        }
        return "Flow offers a passkey option. Complete it from the app-native sign-in."
    }

    func signOut() async throws -> String {
        try await requireSignedIn()
        log.record("signOut:requested")
        let redirect = try await client.signOut()
        await state.refresh()
        guard (try? await client.isSignedIn()) == false else {
            throw CheckFailure("Tokens are still stored after signOut()")
        }
        log.record("signOut:completed", "afterSignOutUrl=\(redirect)", kind: .success)
        return "Session cleared and refresh token revoked"
    }

    /// Confirms the redirect scheme is registered and that the SDK rejects a callback without a code.
    func redirectCallback() async throws -> String {
        guard let scheme = config.callbackScheme else {
            throw CheckFailure("Set THUNDERID_AFTER_SIGN_IN_URL in Config.plist")
        }
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        guard schemes.contains(scheme) else {
            throw CheckFailure("\(scheme) is not registered under CFBundleURLTypes in Info.plist")
        }
        guard let probe = URL(string: "\(scheme)://callback?error=access_denied") else {
            throw CheckFailure("\(scheme) is not a valid URL scheme")
        }
        do {
            _ = try await client.handleRedirectCallback(url: probe)
        } catch let error as ThunderIDError where error.code == .invalidGrant {
            log.record("callback:rejected", "missing code", kind: .success)
            return "\(scheme):// is registered; a callback without a code is rejected"
        }
        throw CheckFailure("handleRedirectCallback accepted a callback without a code")
    }

    // MARK: - Session

    /// Drops the stored expiry so the next `getAccessToken()` sees the token as expired and runs the
    /// refresh_token grant. The SDK has no public "refresh now" call.
    func tokenRefresh() async throws -> String {
        try await requireSignedIn()
        guard storage.retrieve(key: PlaygroundStorage.Key.refreshToken) != nil else {
            throw CheckFailure("No refresh token. App-native sign-in only stores an access token.")
        }
        let before = storage.retrieve(key: PlaygroundStorage.Key.accessToken)
        storage.delete(key: PlaygroundStorage.Key.tokenExpiry)
        let after = try await client.getAccessToken()
        guard after != before else {
            throw CheckFailure("getAccessToken() returned the old token")
        }
        log.record("token:refreshed", "access token rotated", kind: .success)
        return "Rotated the access token with the refresh_token grant"
    }

    func secureStorage() async throws -> String {
        let probe = KeychainStorageAdapter(service: "\(storage.service).check")
        let key = "probe"
        let value = UUID().uuidString
        try probe.store(key: key, value: value)
        defer { probe.delete(key: key) }
        guard probe.retrieve(key: key) == value else {
            throw CheckFailure("Keychain read did not return the value written")
        }
        guard (try? await client.isSignedIn()) == true else {
            return "Keychain round trip works. Sign in to see the SDK's own tokens there."
        }
        guard storage.retrieve(key: PlaygroundStorage.Key.accessToken) != nil else {
            throw CheckFailure("Signed in, but no access token in the Keychain")
        }
        return "Session tokens are in the Keychain (\(storage.service))"
    }

    func userInfo() async throws -> String {
        try await requireSignedIn()
        let user = try await client.getUser()
        log.record("user:loaded", "sub=\(user.sub ?? "?")", kind: .success)
        return "sub \(user.sub ?? "?"), \(user.claims.count) claims"
    }

    // MARK: - UI

    func translations() throws -> String {
        let storageKey = "playground.i18n.check"
        defer { UserDefaults.standard.removeObject(forKey: storageKey) }
        let i18n = ThunderIDI18n(
            bundles: ["fr-FR": ["signIn.button": "Se connecter"]],
            language: "en-US",
            storageKey: storageKey
        )
        let english = i18n.resolve("signIn.button")
        i18n.setLocale("fr-FR")
        let french = i18n.resolve("signIn.button")
        let fallback = i18n.resolve("signOut.button")
        guard english == DefaultStrings.all["signIn.button"], french == "Se connecter",
              fallback == DefaultStrings.all["signOut.button"] else {
            throw CheckFailure("Resolved \"\(english)\" / \"\(french)\" / \"\(fallback)\"")
        }
        return "en-US \"\(english)\", fr-FR \"\(french)\", falls back to English defaults"
    }
}

/// Walks a flow response looking for a passkey action, input or component.
enum FlowInspector {
    static func mentionsPasskey(_ response: EmbeddedFlowResponse) -> Bool {
        var texts: [String?] = []
        for action in response.data?.actions ?? [] {
            texts += [action.id, action.ref, action.type, action.label, action.eventType]
        }
        texts += (response.data?.inputs ?? []).map { $0.name + " " + ($0.type ?? "") }
        texts += collect(response.data?.meta?.components ?? [])
        return texts.contains { $0?.lowercased().contains("passkey") == true }
    }

    private static func collect(_ components: [FlowComponent]) -> [String?] {
        components.flatMap { component in
            [component.id, component.ref, component.type, component.label, component.eventType]
                + collect(component.components ?? [])
        }
    }
}
