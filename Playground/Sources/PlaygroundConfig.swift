// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// Values read from `Config.plist` (copied from `Config.plist.example`). A missing file falls back to
/// a local server with no application, so the playground still opens and every check explains what
/// is missing instead of crashing.
struct PlaygroundConfig {
    static let defaultBaseUrl = "https://localhost:8090"

    let baseUrl: String
    let applicationId: String?
    let clientId: String?
    let afterSignInUrl: String?
    let afterSignOutUrl: String?
    let scopes: [String]
    /// `THUNDERID_ENDPOINT_*` values, keyed by collection path (`users`, `groups`, ...).
    let endpointOverrides: [String: String]
    let isLoaded: Bool

    static func load(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> PlaygroundConfig {
        var values: [String: String] = [:]
        var isLoaded = false
        if let url = bundle.url(forResource: "Config", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url) as? [String: String] {
            values = dict
            isLoaded = true
        }
        // Management keys can also come from launch arguments (`-THUNDERID_ENDPOINT_GROUPS https://...`),
        // which win over Config.plist, to try an override without editing the file.
        for key in ManagementCollection.all.map(\.configKey) {
            if let value = defaults.string(forKey: key) { values[key] = value }
        }
        return PlaygroundConfig(values: values, isLoaded: isLoaded)
    }

    private init(values: [String: String], isLoaded: Bool) {
        func value(_ key: String) -> String? {
            guard let raw = values[key]?.trimmingCharacters(in: .whitespaces),
                  !raw.isEmpty, !raw.hasPrefix("your-") else { return nil }
            return raw
        }
        baseUrl = value("THUNDERID_BASE_URL") ?? Self.defaultBaseUrl
        applicationId = value("THUNDERID_APPLICATION_ID")
        clientId = value("THUNDERID_CLIENT_ID")
        afterSignInUrl = value("THUNDERID_AFTER_SIGN_IN_URL")
        afterSignOutUrl = value("THUNDERID_AFTER_SIGN_OUT_URL")
        scopes = (value("THUNDERID_SCOPES") ?? "openid profile email")
            .split(separator: " ")
            .map(String.init)
        endpointOverrides = ManagementCollection.all.reduce(into: [:]) { overrides, collection in
            overrides[collection.path] = value(collection.configKey)
        }
        self.isLoaded = isLoaded
    }

    /// The custom URL scheme the system browser session listens for, taken from the redirect URI.
    var callbackScheme: String? {
        afterSignInUrl.flatMap { URL(string: $0)?.scheme }
    }

    /// `host:port` for the summary card.
    var hostLabel: String {
        guard let url = URL(string: baseUrl), let host = url.host else { return baseUrl }
        return url.port.map { "\(host):\($0)" } ?? host
    }

    func sdkConfig(storage: StorageAdapter) -> ThunderIDConfig {
        ThunderIDConfig(
            baseUrl: baseUrl,
            clientId: clientId,
            scopes: scopes,
            afterSignInUrl: afterSignInUrl,
            afterSignOutUrl: afterSignOutUrl,
            applicationId: applicationId,
            endpoints: sdkEndpoints,
            storage: storage
        )
    }
}
