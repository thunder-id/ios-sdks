// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Where a new resource goes: an organization unit, a project (whose root organization unit the server
/// places it in), or both. At least one of the two is set.
struct AdminPlacement: Equatable {
    let ouId: String?
    let projectId: String?
}

/// What a create component's form needs from ``AdminCreateHost``.
struct AdminCreateContext<Request, Output> {
    let isSubmitting: Bool
    fileprivate let resolveError: (String) -> String?
    fileprivate let perform: (@escaping (AdminPlacement) -> Request?, @escaping (Output) -> Void) -> Void

    /// The translated message for the current state: no organization unit to create in, or the
    /// failed create. `nil` when there is nothing to report.
    func errorMessage(fallbackKey: String) -> String? {
        resolveError(fallbackKey)
    }

    /// Creates the resource that `build` describes for the resolved organization unit, then calls
    /// `onCreated` with what the server stored. Does nothing while no organization unit is known.
    func submit(_ build: @escaping (String) -> Request, onCreated: @escaping (Output) -> Void) {
        perform({ placement in placement.ouId.map(build) }, onCreated)
    }

    /// Like ``submit(_:onCreated:)``, for the resources the server can place in a project: `build`
    /// receives the organization unit, the project, or both.
    func submit(placement build: @escaping (AdminPlacement) -> Request, onCreated: @escaping (Output) -> Void) {
        perform(build, onCreated)
    }
}

/// Owns a create mutation and resolves the organization unit new resources go into: the `ouId`
/// the application passed, or the signed-in user's own. With `projectScoped`, a component given no
/// `ouId` while a project is current (``ThunderIDState/currentProject``) sends that project instead, and
/// the server places the resource in the project's root organization unit.
struct AdminCreateHost<Request, Output, Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var mutation: ResourceMutation<Request, Output>
    @State private var defaultOuId: String?
    @State private var isOuResolved = false
    let state: ThunderIDState
    let ouId: String?
    let projectScoped: Bool
    let content: (AdminCreateContext<Request, Output>) -> Content

    init(
        state: ThunderIDState,
        ouId: String?,
        projectScoped: Bool = false,
        mutation: @autoclosure @escaping () -> ResourceMutation<Request, Output>,
        @ViewBuilder content: @escaping (AdminCreateContext<Request, Output>) -> Content
    ) {
        _mutation = StateObject(wrappedValue: mutation())
        self.state = state
        self.ouId = ouId
        self.projectScoped = projectScoped
        self.content = content
    }

    private var projectId: String? {
        projectScoped && ouId == nil ? state.currentProject?.id : nil
    }

    private var placement: AdminPlacement? {
        if let projectId { return AdminPlacement(ouId: nil, projectId: projectId) }
        return (ouId ?? defaultOuId).map { AdminPlacement(ouId: $0, projectId: nil) }
    }

    var body: some View {
        content(context).task {
            if ouId == nil { defaultOuId = await state.defaultOuId() }
            isOuResolved = true
        }
    }

    private var context: AdminCreateContext<Request, Output> {
        let mutation = mutation
        let placement = placement
        let isOuMissing = isOuResolved && placement == nil
        let i18n = i18n
        return AdminCreateContext(
            isSubmitting: mutation.isLoading,
            resolveError: { fallbackKey in
                isOuMissing
                    ? i18n.resolve("admin.common.errors.no_ou")
                    : i18n.managementErrorMessage(mutation.error, fallbackKey: fallbackKey)
            },
            perform: { build, onCreated in
                guard let placement, let request = build(placement) else { return }
                Task {
                    if let output = await mutation.mutate(request) {
                        onCreated(output)
                    }
                }
            }
        )
    }
}
