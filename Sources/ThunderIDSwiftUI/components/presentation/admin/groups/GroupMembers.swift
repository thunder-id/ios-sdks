// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A group's members, rendered from the data it is given. Adding is offered when both `onAdd` and
/// `candidates` are set, for each member type `candidates` has an entry for; removing when
/// `onRemove` is set.
public struct BaseGroupMembers<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let members: [GroupMember]
    let candidates: [GroupMemberType: [IdentityCandidate]]?
    let isLoading: Bool
    let error: String?
    let isMutating: Bool
    let title: String?
    let description: String?
    let onAdd: ((GroupMemberInput) -> Void)?
    let onRemove: ((GroupMember) -> Void)?
    let content: ((GroupMembersState) -> Content)?

    init(
        members: [GroupMember],
        candidates: [GroupMemberType: [IdentityCandidate]]? = nil,
        isLoading: Bool = false,
        error: String? = nil,
        isMutating: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onAdd: ((GroupMemberInput) -> Void)? = nil,
        onRemove: ((GroupMember) -> Void)? = nil,
        renderContent: ((GroupMembersState) -> Content)?
    ) {
        self.members = members
        self.candidates = candidates
        self.isLoading = isLoading
        self.error = error
        self.isMutating = isMutating
        self.title = title
        self.description = description
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default table and picker, from the members, the
    ///   candidates, the loading and error state, and the add and remove actions.
    public init(
        members: [GroupMember],
        candidates: [GroupMemberType: [IdentityCandidate]]? = nil,
        isLoading: Bool = false,
        error: String? = nil,
        isMutating: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onAdd: ((GroupMemberInput) -> Void)? = nil,
        onRemove: ((GroupMember) -> Void)? = nil,
        @ViewBuilder content: @escaping (GroupMembersState) -> Content
    ) {
        self.init(
            members: members,
            candidates: candidates,
            isLoading: isLoading,
            error: error,
            isMutating: isMutating,
            title: title,
            description: description,
            onAdd: onAdd,
            onRemove: onRemove,
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

    private var renderState: GroupMembersState {
        GroupMembersState(
            members: members,
            candidates: onAdd == nil ? nil : candidates,
            isLoading: isLoading,
            error: error,
            isMutating: isMutating,
            onAdd: candidates == nil ? nil : onAdd,
            onRemove: onRemove
        )
    }

    @ViewBuilder
    private var defaultBody: some View {
        AdminIdentityTable(
            i18n: i18n,
            identifier: "admin-group-members",
            title: title ?? i18n.resolve("admin.groups.members.title"),
            description: description,
            rows: members.map { AdminRelatedIdentity(id: $0.id, type: $0.type, display: $0.display) },
            emptyText: i18n.resolve("admin.groups.members.empty"),
            addLabel: i18n.resolve("admin.groups.members.add"),
            removeLabelKey: "admin.groups.members.remove_label",
            typeOrder: [.user, .agent, .group],
            candidates: candidates,
            isLoading: isLoading,
            error: error,
            isMutating: isMutating,
            onAdd: onAdd.map { add in { id, type in add(GroupMemberInput(id: id, type: type)) } },
            onRemove: onRemove.map { remove in
                { identity in remove(GroupMember(id: identity.id, type: identity.type, display: identity.display)) }
            }
        )
    }
}

public extension BaseGroupMembers where Content == EmptyView {
    init(
        members: [GroupMember],
        candidates: [GroupMemberType: [IdentityCandidate]]? = nil,
        isLoading: Bool = false,
        error: String? = nil,
        isMutating: Bool = false,
        title: String? = nil,
        description: String? = nil,
        onAdd: ((GroupMemberInput) -> Void)? = nil,
        onRemove: ((GroupMember) -> Void)? = nil
    ) {
        self.init(
            members: members,
            candidates: candidates,
            isLoading: isLoading,
            error: error,
            isMutating: isMutating,
            title: title,
            description: description,
            onAdd: onAdd,
            onRemove: onRemove,
            renderContent: nil
        )
    }
}

/// A group's members, loaded through the management API. Set `editable` to let the signed-in user
/// add users and agents and remove members; it is off by default.
public struct GroupMembers<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    let groupId: String
    let editable: Bool
    let title: String?
    let description: String?
    let content: ((GroupMembersState) -> Content)?

    init(
        groupId: String,
        editable: Bool = false,
        title: String? = nil,
        description: String? = nil,
        renderContent: ((GroupMembersState) -> Content)?
    ) {
        self.groupId = groupId
        self.editable = editable
        self.title = title
        self.description = description
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default table and picker. See ``BaseGroupMembers``.
    public init(
        groupId: String,
        editable: Bool = false,
        title: String? = nil,
        description: String? = nil,
        @ViewBuilder content: @escaping (GroupMembersState) -> Content
    ) {
        self.init(
            groupId: groupId,
            editable: editable,
            title: title,
            description: description,
            renderContent: content
        )
    }

    public var body: some View {
        GroupMembersHost(state: thunderState, props: self).id("\(groupId)|\(editable)")
    }
}

public extension GroupMembers where Content == EmptyView {
    init(
        groupId: String,
        editable: Bool = false,
        title: String? = nil,
        description: String? = nil
    ) {
        self.init(
            groupId: groupId,
            editable: editable,
            title: title,
            description: description,
            renderContent: nil
        )
    }
}

private struct GroupMembersHost<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var members: ResourceQuery<GroupMemberListResponse>
    @StateObject private var users: ResourceQuery<ManagedUserListResponse>
    @StateObject private var agents: ResourceQuery<AgentListResponse>
    @StateObject private var add: ResourceMutation<GroupMembersInput, ManagedGroup>
    @StateObject private var remove: ResourceMutation<GroupMembersInput, ManagedGroup>
    let props: GroupMembers<Content>

    init(state: ThunderIDState, props: GroupMembers<Content>) {
        _members = StateObject(wrappedValue: state.groupMembersQuery(groupId: props.groupId, limit: 100))
        _users = StateObject(wrappedValue: state.usersQuery(limit: 100))
        _agents = StateObject(wrappedValue: state.agentsQuery(limit: 100))
        _add = StateObject(wrappedValue: state.addGroupMembersMutation())
        _remove = StateObject(wrappedValue: state.removeGroupMembersMutation())
        self.props = props
    }

    var body: some View {
        BaseGroupMembers(
            members: members.data?.members ?? [],
            candidates: props.editable
                ? [.user: AdminCandidates.users(users.data), .agent: AdminCandidates.agents(agents.data)]
                : nil,
            isLoading: members.isLoading,
            error: i18n.managementErrorMessage(members.error, fallbackKey: "admin.groups.members.error")
                ?? i18n.managementErrorMessage(
                    add.error ?? remove.error,
                    fallbackKey: "admin.groups.members.update_error"
                ),
            isMutating: add.isLoading || remove.isLoading,
            title: props.title,
            description: props.description,
            onAdd: props.editable ? addMember : nil,
            onRemove: props.editable ? removeMember : nil,
            renderContent: props.content
        )
        .task {
            await members.refetch()
            guard props.editable else { return }
            await users.refetch()
            await agents.refetch()
        }
    }

    private func addMember(_ member: GroupMemberInput) {
        Task { await add.mutate((groupId: props.groupId, members: [member])) }
    }

    private func removeMember(_ member: GroupMember) {
        let input = GroupMemberInput(id: member.id, type: member.type)
        Task { await remove.mutate((groupId: props.groupId, members: [input])) }
    }
}
