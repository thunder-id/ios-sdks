// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A management mutation that refetches the queries whose data it changed. It produces no
/// user-visible side effect: success and failure are reported through its state and return value.
@MainActor
public final class ResourceMutation<Input, Output>: ObservableObject {
    @Published public private(set) var data: Output?
    @Published public private(set) var error: Error?
    @Published public private(set) var isLoading: Bool = false

    private let invalidator: ResourceInvalidator
    private let perform: (Input) async throws -> Output
    private let invalidatedKeys: (Input) -> [[String]]

    init(
        invalidator: ResourceInvalidator,
        invalidatedKeys: @escaping (Input) -> [[String]],
        perform: @escaping (Input) async throws -> Output
    ) {
        self.invalidator = invalidator
        self.invalidatedKeys = invalidatedKeys
        self.perform = perform
    }

    /// Runs the mutation. Never throws: read ``error`` to handle a failure.
    @discardableResult
    public func mutate(_ input: Input) async -> Output? {
        try? await mutateThrowing(input)
    }

    /// Runs the mutation and throws if it fails.
    @discardableResult
    public func mutateThrowing(_ input: Input) async throws -> Output {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let output = try await perform(input)
            data = output
            invalidatedKeys(input).forEach(invalidator.invalidate)
            return output
        } catch {
            self.error = error
            throw error
        }
    }

    /// Clears ``data`` and ``error``.
    public func reset() {
        data = nil
        error = nil
    }
}
