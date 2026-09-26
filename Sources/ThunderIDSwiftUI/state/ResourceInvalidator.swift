// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Lets mutations tell live queries that their data is stale. Invalidation matches on key prefix, so
/// invalidating `["applications"]` reaches every applications list query regardless of its pagination.
@MainActor
public final class ResourceInvalidator {
    private struct Subscription {
        let key: [String]
        let listener: () -> Void
        let isAlive: () -> Bool
    }

    private var subscriptions: [Subscription] = []

    public init() {}

    /// Notifies every live query whose key starts with `prefix`.
    public func invalidate(_ prefix: [String]) {
        subscriptions.removeAll { !$0.isAlive() }
        for subscription in subscriptions where subscription.key.starts(with: prefix) {
            subscription.listener()
        }
    }

    /// Registers `owner` for invalidations matching `key`. The subscription ends when `owner` is released.
    func subscribe<Owner: AnyObject>(_ owner: Owner, key: [String], listener: @escaping (Owner) -> Void) {
        subscriptions.append(
            Subscription(
                key: key,
                listener: { [weak owner] in
                    if let owner { listener(owner) }
                },
                isAlive: { [weak owner] in owner != nil }
            )
        )
    }
}
