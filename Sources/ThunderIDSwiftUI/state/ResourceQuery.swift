// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A management resource fetched on demand and kept fresh. Call ``refetch()`` (for example from a
/// view's `.task`) to load it; a matching mutation refetches it automatically once it has loaded.
/// It depends on no data fetching library: requests run through the SDK's management API.
@MainActor
public final class ResourceQuery<Value>: ObservableObject {
    @Published public private(set) var data: Value?
    @Published public private(set) var error: Error?
    @Published public private(set) var isLoading: Bool = false

    /// Identifies the data. Mutations invalidate by key prefix.
    public let key: [String]

    private let fetch: () async throws -> Value
    private var latestRequest = 0
    private var hasLoaded = false

    init(key: [String], invalidator: ResourceInvalidator, fetch: @escaping () async throws -> Value) {
        self.key = key
        self.fetch = fetch
        invalidator.subscribe(self, key: key) { query in
            guard query.hasLoaded else { return }
            Task { await query.refetch() }
        }
    }

    /// Fetches the resource. Only the latest request updates state, so a slow earlier response
    /// cannot overwrite a newer one.
    @discardableResult
    public func refetch() async -> Value? {
        latestRequest += 1
        let request = latestRequest
        hasLoaded = true
        isLoading = true
        defer {
            if request == latestRequest { isLoading = false }
        }
        do {
            let value = try await fetch()
            if request == latestRequest {
                data = value
                error = nil
            }
            return value
        } catch {
            if request == latestRequest { self.error = error }
            return nil
        }
    }
}
