// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Cache keys for management resources. The SwiftUI wrappers use them to refetch after a mutation,
/// and an application can reuse them as keys in its own cache.
public enum ApplicationQueryKeys {
    public static let application = "application"
    public static let applications = "applications"
}

/// Cache keys for user resources.
public enum UserQueryKeys {
    public static let user = "user"
    public static let users = "users"
    public static let userTypes = "user-types"
}

/// Cache keys for agent resources.
public enum AgentQueryKeys {
    public static let agent = "agent"
    public static let agents = "agents"
    public static let agentTypes = "agent-types"
}

/// Cache keys for group resources. ``memberships`` covers the groups a user or an agent belongs to.
public enum GroupQueryKeys {
    public static let group = "group"
    public static let groups = "groups"
    public static let groupMembers = "group-members"
    public static let memberships = "group-memberships"
}

/// Cache keys for role resources. ``roleAssignments`` also covers the roles assigned to an agent.
public enum RoleQueryKeys {
    public static let role = "role"
    public static let roles = "roles"
    public static let roleAssignments = "role-assignments"
}

/// Cache keys for project resources.
public enum ProjectQueryKeys {
    public static let project = "project"
    public static let projects = "projects"
}

/// Cache keys for organization unit resources. ``organizationUnits`` covers the root units and the
/// children of a unit; ``organizationUnitMembers`` covers a unit's users, groups and roles.
public enum OrganizationUnitQueryKeys {
    public static let organizationUnit = "organization-unit"
    public static let organizationUnits = "organization-units"
    public static let organizationUnitMembers = "organization-unit-members"
}

/// Cache keys for the sharing policies and overlay rules of users, applications, roles and flows.
public enum SharingQueryKeys {
    public static let sharingPolicies = "sharing-policies"
    public static let overlayRules = "overlay-rules"
}
