// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// What a create component's form needs from ``AdminCreateHost``.
struct AdminCreateContext<Request, Output> {
    let isSubmitting: Bool
    fileprivate let resolveError: (String) -> String?
    fileprivate let perform: (@escaping (String) -> Request, @escaping (Output) -> Void) -> Void

    /// The translated message for the current state: no organization unit to create in, or the
    /// failed create. `nil` when there is nothing to report.
    func errorMessage(fallbackKey: String) -> String? {
        resolveError(fallbackKey)
    }

    /// Creates the resource that `build` describes for the resolved organization unit, then calls
    /// `onCreated` with what the server stored. Does nothing while no organization unit is known.
    func submit(_ build: @escaping (String) -> Request, onCreated: @escaping (Output) -> Void) {
        perform(build, onCreated)
    }
}

/// Owns a create mutation and resolves the organization unit new resources go into: the `ouId`
/// the application passed, or the signed-in user's own.
struct AdminCreateHost<Request, Output, Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var mutation: ResourceMutation<Request, Output>
    @State private var defaultOuId: String?
    @State private var isOuResolved = false
    let state: ThunderIDState
    let ouId: String?
    let content: (AdminCreateContext<Request, Output>) -> Content

    init(
        state: ThunderIDState,
        ouId: String?,
        mutation: @autoclosure @escaping () -> ResourceMutation<Request, Output>,
        @ViewBuilder content: @escaping (AdminCreateContext<Request, Output>) -> Content
    ) {
        _mutation = StateObject(wrappedValue: mutation())
        self.state = state
        self.ouId = ouId
        self.content = content
    }

    private var resolvedOuId: String? { ouId ?? defaultOuId }

    var body: some View {
        content(context).task {
            if ouId == nil { defaultOuId = await state.defaultOuId() }
            isOuResolved = true
        }
    }

    private var context: AdminCreateContext<Request, Output> {
        let mutation = mutation
        let ouId = resolvedOuId
        let isOuMissing = isOuResolved && ouId == nil
        let i18n = i18n
        return AdminCreateContext(
            isSubmitting: mutation.isLoading,
            resolveError: { fallbackKey in
                isOuMissing
                    ? i18n.resolve("admin.common.errors.no_ou")
                    : i18n.managementErrorMessage(mutation.error, fallbackKey: fallbackKey)
            },
            perform: { build, onCreated in
                guard let ouId else { return }
                Task {
                    if let output = await mutation.mutate(build(ouId)) {
                        onCreated(output)
                    }
                }
            }
        )
    }
}
