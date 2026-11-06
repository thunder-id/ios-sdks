// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A group's name, description and overview, rendered from the data it is given. Deleting is offered
/// only when `onDelete` is set, and asks for confirmation first. `sections` is rendered under the
/// overview once the group is there; ``GroupDetails`` puts the group's ``GroupMembers`` in it.
public struct BaseGroupDetails<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let group: ManagedGroup?
    let isLoading: Bool
    let error: String?
    let isDeleting: Bool
    let onDelete: (() -> Void)?
    let actions: AnyView?
    let sections: AnyView?
    let content: ((GroupDetailsState) -> Content)?

    init(
        group: ManagedGroup?,
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        onDelete: (() -> Void)? = nil,
        actions: AnyView? = nil,
        sections: AnyView? = nil,
        renderContent: ((GroupDetailsState) -> Content)?
    ) {
        self.group = group
        self.isLoading = isLoading
        self.error = error
        self.isDeleting = isDeleting
        self.onDelete = onDelete
        self.actions = actions
        self.sections = sections
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view, from the group, the loading
    ///   and error state, and the delete action. `sections` is not rendered then.
    public init(
        group: ManagedGroup?,
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        onDelete: (() -> Void)? = nil,
        actions: AnyView? = nil,
        sections: AnyView? = nil,
        @ViewBuilder content: @escaping (GroupDetailsState) -> Content
    ) {
        self.init(
            group: group,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            onDelete: onDelete,
            actions: actions,
            sections: sections,
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

    private var renderState: GroupDetailsState {
        GroupDetailsState(
            group: group,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            onDelete: group != nil ? onDelete : nil
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        if let group {
            details(group)
        } else {
            AdminSection(identifier: "admin-group-details") {
                if isLoading {
                    AdminLoadingRow(label: i18n.resolve("admin.common.loading"))
                } else {
                    AdminErrorBanner(message: error ?? i18n.resolve("admin.common.errors.not_found"))
                }
            }
        }
    }

    private func details(_ group: ManagedGroup) -> some View {
        AdminSection(
            identifier: "admin-group-details",
            title: group.name,
            description: group.description,
            actions: { headerActions(group) },
            content: {
                if let error {
                    AdminErrorBanner(message: error)
                }
                AdminPanel(title: i18n.resolve("admin.groups.details.overview")) {
                    AdminDetailList(items: [
                        (i18n.resolve("admin.common.columns.organization_unit"), group.ouHandle ?? group.ouId)
                    ])
                }
                if let sections {
                    sections
                }
            }
        )
    }

    private func headerActions(_ group: ManagedGroup) -> some View {
        HStack(spacing: 8) {
            actions
            if let onDelete {
                AdminConfirmButton(
                    i18n: i18n,
                    title: i18n.resolve("admin.groups.details.delete.action"),
                    confirmText: i18n.resolve("admin.groups.details.delete.confirm", ["name": group.name]),
                    isLoading: isDeleting,
                    identifier: "admin-group-details-delete",
                    onConfirm: onDelete
                )
            }
        }
    }
}

public extension BaseGroupDetails where Content == EmptyView {
    init(
        group: ManagedGroup?,
        isLoading: Bool = false,
        error: String? = nil,
        isDeleting: Bool = false,
        onDelete: (() -> Void)? = nil,
        actions: AnyView? = nil,
        sections: AnyView? = nil
    ) {
        self.init(
            group: group,
            isLoading: isLoading,
            error: error,
            isDeleting: isDeleting,
            onDelete: onDelete,
            actions: actions,
            sections: sections,
            renderContent: nil
        )
    }
}

/// A group's details and members, loaded through the management API. Set `editable` to let the
/// signed-in user add and remove members, and `deletable` to let them delete the group; both are off
/// by default, and a delete asks for confirmation first. `administrationMode` chooses how members are
/// removed and how the group is deleted: `.flow` runs the flows the server configures (the group
/// deletion flow revokes what the members held through the group first), falling back to the API when
/// none is configured. It defaults to `.native`. The members are offered from the group's organization
/// unit. With `content`, the custom UI replaces the whole view, members included.
public struct GroupDetails<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let groupId: String
    let administrationMode: AdministrationMode
    let editable: Bool
    let deletable: Bool
    let onDeleted: (() -> Void)?
    let actions: AnyView?
    let content: ((GroupDetailsState) -> Content)?

    init(
        groupId: String,
        administrationMode: AdministrationMode = .native,
        editable: Bool = false,
        deletable: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        renderContent: ((GroupDetailsState) -> Content)?
    ) {
        self.groupId = groupId
        self.administrationMode = administrationMode
        self.editable = editable
        self.deletable = deletable
        self.onDeleted = onDeleted
        self.actions = actions
        self.content = renderContent
    }

    /// - Parameters:
    ///   - administrationMode: How members are removed and the group is deleted. See ``AdministrationMode``.
    ///   - content: Renders custom UI in place of the default view. See ``BaseGroupDetails``.
    public init(
        groupId: String,
        administrationMode: AdministrationMode = .native,
        editable: Bool = false,
        deletable: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil,
        @ViewBuilder content: @escaping (GroupDetailsState) -> Content
    ) {
        self.init(
            groupId: groupId,
            administrationMode: administrationMode,
            editable: editable,
            deletable: deletable,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: content
        )
    }

    public var body: some View {
        GroupDetailsHost(state: thunderState, props: self).id("\(groupId)|\(administrationMode.rawValue)")
    }
}

public extension GroupDetails where Content == EmptyView {
    init(
        groupId: String,
        administrationMode: AdministrationMode = .native,
        editable: Bool = false,
        deletable: Bool = false,
        onDeleted: (() -> Void)? = nil,
        actions: AnyView? = nil
    ) {
        self.init(
            groupId: groupId,
            administrationMode: administrationMode,
            editable: editable,
            deletable: deletable,
            onDeleted: onDeleted,
            actions: actions,
            renderContent: nil
        )
    }
}

private struct GroupDetailsHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var group: ResourceQuery<ManagedGroup>
    @StateObject private var deletion: ResourceMutation<String, Void>
    let props: GroupDetails<Content>

    init(state: ThunderIDState, props: GroupDetails<Content>) {
        _group = StateObject(wrappedValue: state.groupQuery(id: props.groupId))
        _deletion = StateObject(
            wrappedValue: state.deleteGroupMutation(administrationMode: props.administrationMode)
        )
        self.props = props
    }

    var body: some View {
        BaseGroupDetails(
            group: group.data,
            isLoading: group.isLoading,
            error: i18n.managementErrorMessage(group.error, fallbackKey: "admin.groups.details.error")
                ?? i18n.managementErrorMessage(deletion.error, fallbackKey: "admin.groups.details.delete.error"),
            isDeleting: deletion.isLoading,
            onDelete: props.deletable ? delete : nil,
            actions: props.actions,
            sections: AnyView(
                GroupMembers(
                    groupId: props.groupId,
                    editable: props.editable && group.data != nil,
                    administrationMode: props.administrationMode,
                    ouId: group.data?.ouId
                )
            ),
            renderContent: props.content
        )
        .task { await group.refetch() }
    }

    private func delete() {
        Task {
            if await deletion.mutate(props.groupId) != nil {
                props.onDeleted?()
            }
        }
    }
}
