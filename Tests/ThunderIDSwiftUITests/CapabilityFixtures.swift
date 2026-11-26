// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
@testable import ThunderIDSwiftUI

extension Capabilities {
    /// Capabilities that allow `actions` on each resource and nothing else.
    static func allowing(_ actions: [String: [String]]) -> Capabilities {
        Capabilities(
            scope: CapabilityScope(type: "deployment"),
            resources: actions.mapValues { Dictionary(uniqueKeysWithValues: $0.map { ($0, true) }) }
        )
    }

    /// Every action on every resource the management components use.
    static let everything = allowing(
        Dictionary(
            uniqueKeysWithValues: ["app", "user", "group", "role", "agent", "ou", "project", "flow"]
                .map { ($0, ["view", "create", "update", "delete"]) }
        )
    )
}

extension ThunderIDState {
    /// Lets the signed-in user do everything, as a test that is not about capabilities expects.
    @MainActor
    @discardableResult
    func allowingEverything() -> ThunderIDState {
        capabilities.capabilities = .everything
        return self
    }
}
