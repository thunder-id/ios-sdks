// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

@main
struct PlaygroundApp: App {
    private let sdkConfig: ThunderIDConfig
    @StateObject private var log: EventLog
    @StateObject private var checks: ChecksModel

    init() {
        let config = PlaygroundConfig.load()
        let log = EventLog()
        let storage = PlaygroundStorage(vendor: VendorConstants.vendorPrefix, log: log)
        sdkConfig = config.sdkConfig(storage: storage)
        _log = StateObject(wrappedValue: log)
        _checks = StateObject(wrappedValue: ChecksModel(config: config, storage: storage, log: log))
        log.record("config:loaded", config.isLoaded ? config.baseUrl : "Config.plist missing, using defaults")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(log)
                .environmentObject(checks)
                .environmentObject(checks.ids)
                .thunderIDProvider(config: sdkConfig)
                .tint(Palette.primary)
        }
    }
}
