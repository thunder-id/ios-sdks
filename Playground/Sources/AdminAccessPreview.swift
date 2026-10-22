// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

/// Group and role components. The sample membership stories keep their rows in local state, so
/// adding and removing in the preview behaves as it would against the server.
struct AccessAdminPreview: View {
    let id: String
    let values: PropValues
    let onEvent: (String) -> Void
    @State private var selected: String?
    @State private var members = AdminSamples.members
    @State private var assignments = AdminSamples.assignments

    private static let memberCandidates: [GroupMemberType: [IdentityCandidate]] = [
        .user: AdminSamples.userCandidates,
        .agent: AdminSamples.agentCandidates
    ]
    private static let assigneeCandidates: [RoleAssigneeType: [IdentityCandidate]] = [
        .user: AdminSamples.userCandidates,
        .group: AdminSamples.groupCandidates,
        .agent: AdminSamples.agentCandidates
    ]

    var body: some View {
        switch id {
        case "groupList": groupList
        case "groupCreate": groupCreate
        case "groupMembers": groupMembers
        case "roleList": roleList
        case "roleCreate": roleCreate
        case "rolePermissions": rolePermissions
        default: roleAssignments
        }
    }

    // MARK: - Groups

    @ViewBuilder private var groupList: some View {
        if values.isLive {
            GroupList(
                limit: values.limit,
                title: values.optional("title"),
                description: values.optional("description"),
                selectedGroupId: selected
            ) { select($0.id, $0.name) }
        } else {
            BaseGroupList(
                groups: values.isSampleEmpty ? [] : AdminSamples.groups,
                isLoading: values.isSampleLoading,
                error: values.sampleError,
                title: values.optional("title"),
                description: values.optional("description"),
                limit: values.limit,
                totalResults: values.isSampleEmpty ? 0 : AdminSamples.groups.count,
                selectedGroupId: selected,
                onPageChange: { onEvent("onPageChange: \($0)") },
                onSelect: { select($0.id, $0.name) }
            )
        }
    }

    @ViewBuilder private var groupCreate: some View {
        if values.isLive {
            GroupCreate(
                ouId: values.optional("ouId"),
                title: values.optional("title"),
                description: values.optional("description"),
                onCancel: { onEvent("onCancel") },
                onCreated: { group in onEvent("onCreated: \(group.id)") }
            )
        } else {
            BaseGroupCreate(
                error: values.sampleError,
                isSubmitting: values.isSubmitting,
                title: values.optional("title"),
                description: values.optional("description"),
                onCancel: { onEvent("onCancel") },
                onSubmit: { submission in onEvent("onSubmit: \(submission.name)") }
            )
        }
    }

    @ViewBuilder private var groupMembers: some View {
        let editable = values.flag("editable")
        if values.isLive {
            GroupMembers(
                groupId: values.text("groupId"),
                editable: editable,
                title: values.optional("title"),
                description: values.optional("description")
            )
        } else {
            BaseGroupMembers(
                members: values.isSampleEmpty ? [] : members,
                candidates: editable ? Self.memberCandidates : nil,
                isLoading: values.isSampleLoading,
                error: values.sampleError,
                title: values.optional("title"),
                description: values.optional("description"),
                onAdd: editable ? addMember : nil,
                onRemove: editable ? removeMember : nil
            )
        }
    }

    // MARK: - Roles

    @ViewBuilder private var roleList: some View {
        if values.isLive {
            RoleList(
                limit: values.limit,
                title: values.optional("title"),
                description: values.optional("description"),
                selectedRoleId: selected
            ) { select($0.id, $0.name) }
        } else {
            BaseRoleList(
                roles: values.isSampleEmpty ? [] : AdminSamples.roles,
                isLoading: values.isSampleLoading,
                error: values.sampleError,
                title: values.optional("title"),
                description: values.optional("description"),
                limit: values.limit,
                totalResults: values.isSampleEmpty ? 0 : AdminSamples.roles.count,
                selectedRoleId: selected,
                onPageChange: { onEvent("onPageChange: \($0)") },
                onSelect: { select($0.id, $0.name) }
            )
        }
    }

    @ViewBuilder private var roleCreate: some View {
        if values.isLive {
            RoleCreate(
                ouId: values.optional("ouId"),
                title: values.optional("title"),
                description: values.optional("description"),
                onCancel: { onEvent("onCancel") },
                onCreated: { role in onEvent("onCreated: \(role.id)") }
            )
        } else {
            BaseRoleCreate(
                error: values.sampleError,
                isSubmitting: values.isSubmitting,
                title: values.optional("title"),
                description: values.optional("description"),
                onCancel: { onEvent("onCancel") },
                onSubmit: { submission in onEvent("onSubmit: \(submission.name)") }
            )
        }
    }

    @ViewBuilder private var rolePermissions: some View {
        if values.isLive {
            RolePermissions(
                roleId: values.text("roleId"),
                title: values.optional("title"),
                description: values.optional("description")
            )
        } else {
            BaseRolePermissions(
                permissions: values.isSampleLoading ? [] : AdminSamples.permissions,
                resourceServerNames: AdminSamples.resourceServerNames,
                isLoading: values.isSampleLoading,
                error: values.sampleError,
                title: values.optional("title"),
                description: values.optional("description")
            )
        }
    }

    @ViewBuilder private var roleAssignments: some View {
        let editable = values.flag("editable")
        if values.isLive {
            RoleAssignments(
                roleId: values.text("roleId"),
                editable: editable,
                title: values.optional("title"),
                description: values.optional("description")
            )
        } else {
            BaseRoleAssignments(
                assignments: values.isSampleEmpty ? [] : assignments,
                candidates: editable ? Self.assigneeCandidates : nil,
                isLoading: values.isSampleLoading,
                error: values.sampleError,
                title: values.optional("title"),
                description: values.optional("description"),
                onAssign: editable ? assign : nil,
                onUnassign: editable ? unassign : nil
            )
        }
    }

    // MARK: - Sample mutations

    private func select(_ id: String, _ name: String) {
        selected = id
        onEvent("onSelect: \(name)")
    }

    private func addMember(_ input: GroupMemberInput) {
        members.append(GroupMember(id: input.id, type: input.type, display: label(for: input.id)))
        onEvent("onAdd: \(input.type.rawValue) \(input.id)")
    }

    private func removeMember(_ member: GroupMember) {
        members.removeAll { $0 == member }
        onEvent("onRemove: \(member.id)")
    }

    private func assign(_ input: RoleAssignmentInput) {
        assignments.append(RoleAssignment(id: input.id, type: input.type, display: label(for: input.id)))
        onEvent("onAssign: \(input.type.rawValue) \(input.id)")
    }

    private func unassign(_ assignment: RoleAssignment) {
        assignments.removeAll { $0 == assignment }
        onEvent("onUnassign: \(assignment.id)")
    }

    private func label(for id: String) -> String? {
        (AdminSamples.userCandidates + AdminSamples.agentCandidates + AdminSamples.groupCandidates)
            .first { $0.id == id }?
            .label
    }
}
