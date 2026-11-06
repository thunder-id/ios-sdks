// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// The sharing policies of one resource, each with its reach as the server records it, rendered from the
/// data it is given. Adding, editing and deleting are offered only when their callbacks are set, never
/// for a read-only policy, and a delete asks for confirmation first. `overlay`, when given, shows the
/// resolved overlay rules for one organization unit, read only.
public struct BaseSharingPolicies<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let policies: [SharingPolicy]
    let isLoading: Bool
    let error: String?
    let title: String?
    let limit: Int
    let offset: Int
    let totalResults: Int?
    let onPageChange: ((Int) -> Void)?
    let overlay: ResolvedOverlay?
    let isMutating: Bool
    let onCreate: ((SharingPolicyRequest) -> Void)?
    let onUpdate: ((SharingPolicy, SharingPolicyUpdateRequest) -> Void)?
    let onDelete: ((SharingPolicy) -> Void)?
    let content: ((SharingPoliciesState) -> Content)?

    @State private var isAdding = false
    @State private var editingId: String?

    init(
        policies: [SharingPolicy],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        overlay: ResolvedOverlay? = nil,
        isMutating: Bool = false,
        onCreate: ((SharingPolicyRequest) -> Void)? = nil,
        onUpdate: ((SharingPolicy, SharingPolicyUpdateRequest) -> Void)? = nil,
        onDelete: ((SharingPolicy) -> Void)? = nil,
        renderContent: ((SharingPoliciesState) -> Content)?
    ) {
        self.policies = policies
        self.isLoading = isLoading
        self.error = error
        self.title = title
        self.limit = limit
        self.offset = offset
        self.totalResults = totalResults
        self.onPageChange = onPageChange
        self.overlay = overlay
        self.isMutating = isMutating
        self.onCreate = onCreate
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view, from the policies, the paging,
    ///   the overlay rules, the loading and error state, and the create, update and delete actions.
    public init(
        policies: [SharingPolicy],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        overlay: ResolvedOverlay? = nil,
        isMutating: Bool = false,
        onCreate: ((SharingPolicyRequest) -> Void)? = nil,
        onUpdate: ((SharingPolicy, SharingPolicyUpdateRequest) -> Void)? = nil,
        onDelete: ((SharingPolicy) -> Void)? = nil,
        @ViewBuilder content: @escaping (SharingPoliciesState) -> Content
    ) {
        self.init(
            policies: policies,
            isLoading: isLoading,
            error: error,
            title: title,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            onPageChange: onPageChange,
            overlay: overlay,
            isMutating: isMutating,
            onCreate: onCreate,
            onUpdate: onUpdate,
            onDelete: onDelete,
            renderContent: content
        )
    }

    public var body: some View {
        if let content {
            content(renderState)
        } else {
            defaultBody
        }
    }

    private var renderState: SharingPoliciesState {
        let i18n = i18n
        return SharingPoliciesState(
            policies: policies,
            isLoading: isLoading,
            error: error,
            limit: limit,
            offset: offset,
            totalResults: totalResults ?? policies.count,
            onPageChange: onPageChange,
            overlay: overlay,
            describe: { SharingScope.describe($0, i18n: i18n) },
            isMutating: isMutating,
            onCreate: onCreate,
            onUpdate: onUpdate,
            onDelete: onDelete
        )
    }

    private var defaultBody: some View {
        AdminSection(
            identifier: "admin-sharing-policies",
            title: title ?? i18n.resolve("admin.sharing.title"),
            actions: {
                if onCreate != nil, !isAdding {
                    Button(i18n.resolve("admin.sharing.add")) { isAdding = true }
                        .disabled(isMutating)
                        .accessibilityIdentifier("admin-sharing-add")
                }
            },
            content: {
                if isAdding, let onCreate {
                    SharingPolicyForm(
                        i18n: i18n,
                        policy: nil,
                        isSubmitting: isMutating,
                        onCancel: { isAdding = false },
                        onSubmit: { draft in
                            onCreate(SharingPolicyRequest(childUnits: draft.childUnits))
                            isAdding = false
                        }
                    )
                }
                AdminTable(
                    identifier: "admin-sharing-policies",
                    rows: policies,
                    rowId: { $0.id ?? "" },
                    isLoading: isLoading,
                    error: error,
                    emptyText: i18n.resolve("admin.sharing.empty"),
                    pagination: onPageChange.map {
                        AdminPagination(
                            i18n: i18n,
                            limit: limit,
                            offset: offset,
                            total: totalResults ?? policies.count,
                            onChange: $0
                        )
                    },
                    row: { policy in row(policy) },
                    i18n: i18n
                )
                if let overlay {
                    SharingOverlayPanel(i18n: i18n, overlay: overlay)
                }
            }
        )
    }

    @ViewBuilder
    private func row(_ policy: SharingPolicy) -> some View {
        if editingId != nil, editingId == policy.id, let onUpdate {
            SharingPolicyForm(
                i18n: i18n,
                policy: policy,
                isSubmitting: isMutating,
                onCancel: { editingId = nil },
                onSubmit: { draft in
                    onUpdate(
                        policy,
                        SharingPolicyUpdateRequest(
                            version: policy.version ?? 0,
                            allUnits: draft.allUnits,
                            childUnits: draft.childUnits,
                            otherTreeRoots: policy.otherTreeRoots
                        )
                    )
                    editingId = nil
                }
            )
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AdminRowLabel(title: SharingScope.describe(policy, i18n: i18n), details: details(policy))
                Spacer(minLength: 8)
                if policy.isReadOnly != true {
                    rowActions(policy)
                }
            }
        }
    }

    private func details(_ policy: SharingPolicy) -> [String] {
        [
            policy.stage == "reshare" ? i18n.resolve("admin.sharing.stage.reshare") : "",
            policy.initiatingOuId.map { i18n.resolve("admin.sharing.issuer", ["unit": $0]) } ?? "",
            policy.isReadOnly == true ? i18n.resolve("admin.sharing.read_only") : ""
        ]
    }

    private func rowActions(_ policy: SharingPolicy) -> some View {
        HStack(spacing: 8) {
            if onUpdate != nil {
                Button(i18n.resolve("admin.sharing.edit")) { editingId = policy.id }
                    .disabled(isMutating)
                    .accessibilityIdentifier("admin-sharing-edit-\(policy.id ?? "")")
            }
            if let onDelete {
                AdminConfirmButton(
                    i18n: i18n,
                    title: i18n.resolve("admin.sharing.delete.action"),
                    confirmText: i18n.resolve("admin.sharing.delete.confirm"),
                    isLoading: false,
                    identifier: "admin-sharing-delete-\(policy.id ?? "")"
                ) { onDelete(policy) }
                .disabled(isMutating)
            }
        }
    }
}

public extension BaseSharingPolicies where Content == EmptyView {
    init(
        policies: [SharingPolicy],
        isLoading: Bool = false,
        error: String? = nil,
        title: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        overlay: ResolvedOverlay? = nil,
        isMutating: Bool = false,
        onCreate: ((SharingPolicyRequest) -> Void)? = nil,
        onUpdate: ((SharingPolicy, SharingPolicyUpdateRequest) -> Void)? = nil,
        onDelete: ((SharingPolicy) -> Void)? = nil
    ) {
        self.init(
            policies: policies,
            isLoading: isLoading,
            error: error,
            title: title,
            limit: limit,
            offset: offset,
            totalResults: totalResults,
            onPageChange: onPageChange,
            overlay: overlay,
            isMutating: isMutating,
            onCreate: onCreate,
            onUpdate: onUpdate,
            onDelete: onDelete,
            renderContent: nil
        )
    }
}

/// The sharing policies of one user, application, role or flow, loaded through that resource type's
/// sharing operations. Set `editable` to let the signed-in user add, edit and delete policies; it is off
/// by default, and a delete asks for confirmation first. With `ouId`, the resolved overlay rules for that
/// organization unit are shown too, read only. The details components do not embed it: place it where
/// the app wants it.
public struct SharingPolicies<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let resourceType: SharingResourceType
    let resourceId: String
    let ouId: String?
    let limit: Int
    let editable: Bool
    let title: String?
    let content: ((SharingPoliciesState) -> Content)?

    init(
        resourceType: SharingResourceType,
        resourceId: String,
        ouId: String? = nil,
        limit: Int = 20,
        editable: Bool = false,
        title: String? = nil,
        renderContent: ((SharingPoliciesState) -> Content)?
    ) {
        self.resourceType = resourceType
        self.resourceId = resourceId
        self.ouId = ouId
        self.limit = limit
        self.editable = editable
        self.title = title
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view. See ``BaseSharingPolicies``.
    public init(
        resourceType: SharingResourceType,
        resourceId: String,
        ouId: String? = nil,
        limit: Int = 20,
        editable: Bool = false,
        title: String? = nil,
        @ViewBuilder content: @escaping (SharingPoliciesState) -> Content
    ) {
        self.init(
            resourceType: resourceType,
            resourceId: resourceId,
            ouId: ouId,
            limit: limit,
            editable: editable,
            title: title,
            renderContent: content
        )
    }

    public var body: some View {
        SharingPoliciesHost(state: thunderState, props: self)
            .id("\(resourceType.rawValue)|\(resourceId)|\(ouId ?? "")|\(limit)")
    }
}

public extension SharingPolicies where Content == EmptyView {
    init(
        resourceType: SharingResourceType,
        resourceId: String,
        ouId: String? = nil,
        limit: Int = 20,
        editable: Bool = false,
        title: String? = nil
    ) {
        self.init(
            resourceType: resourceType,
            resourceId: resourceId,
            ouId: ouId,
            limit: limit,
            editable: editable,
            title: title,
            renderContent: nil
        )
    }
}

private struct SharingPoliciesHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var overlay: ResourceQuery<ResolvedOverlay>
    @StateObject private var creation:
        ResourceMutation<(resourceId: String, request: SharingPolicyRequest), SharingPolicy>
    @StateObject private var update: ResourceMutation<SharingPolicyUpdateInput, SharingPolicy>
    @StateObject private var deletion: ResourceMutation<(resourceId: String, policyId: String), Void>
    @State private var offset = 0
    let state: ThunderIDState
    let props: SharingPolicies<Content>

    init(state: ThunderIDState, props: SharingPolicies<Content>) {
        let type = props.resourceType
        _overlay = StateObject(
            wrappedValue: state.overlayRulesQuery(
                resourceType: type,
                resourceId: props.resourceId,
                ouId: props.ouId ?? ""
            )
        )
        _creation = StateObject(wrappedValue: state.createSharingPolicyMutation(resourceType: type))
        _update = StateObject(wrappedValue: state.updateSharingPolicyMutation(resourceType: type))
        _deletion = StateObject(wrappedValue: state.deleteSharingPolicyMutation(resourceType: type))
        self.state = state
        self.props = props
    }

    var body: some View {
        let query = state.sharingPoliciesQuery(
            resourceType: props.resourceType,
            resourceId: props.resourceId,
            limit: props.limit,
            offset: offset
        )
        AdminQueryReader(query) { policies in
            BaseSharingPolicies(
                policies: policies.data?.policies ?? [],
                isLoading: policies.isLoading,
                error: i18n.managementErrorMessage(policies.error, fallbackKey: "admin.sharing.error")
                    ?? mutationError
                    ?? i18n.managementErrorMessage(overlay.error, fallbackKey: "admin.sharing.overlay.error"),
                title: props.title,
                limit: props.limit,
                offset: offset,
                totalResults: policies.data?.totalResults,
                onPageChange: { offset = $0 },
                overlay: overlay.data,
                isMutating: creation.isLoading || update.isLoading || deletion.isLoading,
                onCreate: props.editable ? create : nil,
                onUpdate: props.editable ? save : nil,
                onDelete: props.editable ? delete : nil,
                renderContent: props.content
            )
        }
        .id(offset)
        .task {
            if props.ouId != nil { await overlay.refetch() }
        }
    }

    private var mutationError: String? {
        [creation.error, update.error, deletion.error]
            .compactMap {
                i18n.managementErrorMessage($0, fallbackKey: "admin.sharing.update_error", codeKeys: sharingErrorKeys)
            }
            .first
    }

    private func create(_ request: SharingPolicyRequest) {
        Task { await creation.mutate((resourceId: props.resourceId, request: request)) }
    }

    private func save(_ policy: SharingPolicy, _ request: SharingPolicyUpdateRequest) {
        guard let policyId = policy.id else { return }
        Task {
            await update.mutate(
                SharingPolicyUpdateInput(resourceId: props.resourceId, policyId: policyId, request: request)
            )
        }
    }

    private func delete(_ policy: SharingPolicy) {
        guard let policyId = policy.id else { return }
        Task { await deletion.mutate((resourceId: props.resourceId, policyId: policyId)) }
    }
}

/// The server's codes for an edit against a stale version, and for a second policy from the same
/// organization unit, for each resource type.
private let sharingErrorKeys: [String: String] = [
    "USR-1032": "admin.sharing.errors.conflict",
    "APP-1054": "admin.sharing.errors.conflict",
    "ROL-1024": "admin.sharing.errors.conflict",
    "FLM-1032": "admin.sharing.errors.conflict",
    "USR-1031": "admin.sharing.errors.exists",
    "APP-1053": "admin.sharing.errors.exists",
    "ROL-1023": "admin.sharing.errors.exists",
    "FLM-1031": "admin.sharing.errors.exists"
]
