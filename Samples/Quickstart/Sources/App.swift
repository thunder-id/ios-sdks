// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

@main
struct ThunderIDB2CApp: App {
    private let config: ThunderIDConfig = {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: String] else {
            fatalError(
                "Config.plist not found — copy Config.plist.example to Sources/Config.plist and fill in your values"
            )
        }
        let attestationEnabled = (dict["THUNDERID_ATTESTATION_ENABLED"] ?? "").lowercased() == "true"
        let attestationProvider = AppAttestTokenProvider()
        return ThunderIDConfig(
            baseUrl: dict["THUNDERID_BASE_URL"] ?? "",
            scopes: ["openid", "profile", "email"],
            applicationId: dict["THUNDERID_APPLICATION_ID"],
            attestationEnabled: attestationEnabled,
            attestationTokenProvider: attestationEnabled ? attestationProvider.requestToken : nil
        )
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .thunderIDProvider(config: config)
                .tint(Color(red: 0.212, green: 0.533, blue: 1.0))
        }
    }
}
