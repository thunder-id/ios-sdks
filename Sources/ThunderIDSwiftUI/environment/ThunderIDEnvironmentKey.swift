// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Environment key for the ThunderID auth state (spec §7.2).
struct ThunderIDStateKey: EnvironmentKey {
    static let defaultValue: ThunderIDState? = nil
}

public extension EnvironmentValues {
    var thunderState: ThunderIDState? {
        get { self[ThunderIDStateKey.self] }
        set { self[ThunderIDStateKey.self] = newValue }
    }
}
