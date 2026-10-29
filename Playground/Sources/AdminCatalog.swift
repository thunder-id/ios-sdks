// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderIDSwiftUI

/// The IDs the live admin stories start from: whatever the management checks found.
struct AdminStoryIds {
    var groupId = ""
    var roleId = ""
    var userId = ""
    var agentId = ""
    var applicationId = ""
}

/// Stories for the admin components. Each has a `sample` source, which renders the `Base*` view
/// with sample records in a chosen state, and a `live` source, which renders the connected view
/// against the management API with the signed-in user's token.
extension ExplorerCatalog {
    static func admin(ids: AdminStoryIds) -> [ComponentSpec] {
        [
            list("userList", "UserList", group: "Admin · Users", item: "users"),
            detail("userDetails", "UserDetails", group: "Admin · Users", idKey: "userId", id: ids.userId),
            create("userCreate", "UserCreate", group: "Admin · Users"),
            list("groupList", "GroupList", group: "Admin · Groups", item: "groups"),
            create("groupCreate", "GroupCreate", group: "Admin · Groups"),
            membership("groupMembers", "GroupMembers", group: "Admin · Groups", idKey: "groupId", id: ids.groupId),
            list("roleList", "RoleList", group: "Admin · Roles", item: "roles"),
            create("roleCreate", "RoleCreate", group: "Admin · Roles"),
            detail("rolePermissions", "RolePermissions", group: "Admin · Roles", idKey: "roleId", id: ids.roleId),
            membership("roleAssignments", "RoleAssignments", group: "Admin · Roles", idKey: "roleId", id: ids.roleId),
            list("agentList", "AgentList", group: "Admin · Agents", item: "agents"),
            detail("agentDetails", "AgentDetails", group: "Admin · Agents", idKey: "agentId", id: ids.agentId),
            create("agentCreate", "AgentCreate", group: "Admin · Agents"),
            list("applicationList", "ApplicationList", group: "Admin · Applications", item: "applications"),
            detail(
                "applicationDetails",
                "ApplicationDetails",
                group: "Admin · Applications",
                idKey: "applicationId",
                id: ids.applicationId
            ),
            create("applicationCreate", "ApplicationCreate", group: "Admin · Applications")
        ]
    }

    static let forbidden = DefaultStrings.all["admin.common.errors.forbidden"] ?? "You do not have permission."

    // MARK: - Spec shapes

    private static let sourceControl = StoryControl(name: "source", kind: .options(["sample", "live"]))
    private static let textControls = [
        StoryControl(name: "title", kind: .text),
        StoryControl(name: "description", kind: .text)
    ]
    private static let errorControl = StoryControl(name: "error", kind: .text)
    private static let common: PropValues = ["source": "sample", "state": "data", "title": "", "description": ""]

    private static func stateControl(_ states: [String]) -> StoryControl {
        StoryControl(name: "state", kind: .options(states))
    }

    private static func states(_ names: [String], live: Bool = true) -> [Story] {
        let samples = names.map { name in
            Story(id: name, name: storyName(name), preset: ["source": "sample", "state": name])
        }
        return live ? samples + [Story(id: "live", name: "Live", preset: ["source": "live"])] : samples
    }

    private static func storyName(_ state: String) -> String {
        switch state {
        case "data": return "Sample"
        case "submitting": return "Submitting"
        default: return state.prefix(1).uppercased() + state.dropFirst()
        }
    }

    /// A paged table: `Base*List` with sample rows, or the connected list.
    private static func list(_ id: String, _ name: String, group: String, item: String) -> ComponentSpec {
        ComponentSpec(
            id: id,
            name: name,
            group: group,
            defaults: common.merging(["limit": "20", "error": forbidden]) { _, new in new },
            controls: [sourceControl, stateControl(["data", "loading", "empty", "error"])]
                + textControls
                + [StoryControl(name: "limit", kind: .options(["5", "20", "50"])), errorControl],
            stories: states(["data", "loading", "empty", "error"]),
            isTall: true
        ) { values in AdminSnippets.list(name: name, item: item, values: values) }
    }

    /// One resource by ID: details or permissions.
    private static func detail(_ id: String, _ name: String, group: String, idKey: String, id value: String)
        -> ComponentSpec {
        ComponentSpec(
            id: id,
            name: name,
            group: group,
            defaults: common.merging([idKey: value, "error": forbidden, "deletable": "false"]) { _, new in new },
            controls: [sourceControl, stateControl(["data", "loading", "error"])]
                + (name == "RolePermissions" ? textControls : [StoryControl(name: "deletable", kind: .bool)])
                + [StoryControl(name: idKey, kind: .text), errorControl],
            stories: states(["data", "loading", "error"]),
            isTall: true
        ) { values in AdminSnippets.detail(name: name, idKey: idKey, values: values) }
    }

    /// A create form: `Base*Create` with a submit callback, or the connected form that creates for real.
    private static func create(_ id: String, _ name: String, group: String) -> ComponentSpec {
        ComponentSpec(
            id: id,
            name: name,
            group: group,
            defaults: common.merging(["state": "idle", "error": forbidden, "ouId": ""]) { _, new in new },
            controls: [sourceControl, stateControl(["idle", "submitting", "error"])]
                + textControls
                + [StoryControl(name: "ouId", kind: .text), errorControl],
            stories: states(["idle", "submitting", "error"]).map { story in
                story.id == "idle" ? Story(id: "idle", name: "Sample", preset: story.preset) : story
            },
            isTall: true
        ) { values in AdminSnippets.create(name: name, values: values) }
    }

    /// Group members or role assignments, read-only or with the add and remove pickers.
    private static func membership(_ id: String, _ name: String, group: String, idKey: String, id value: String)
        -> ComponentSpec {
        ComponentSpec(
            id: id,
            name: name,
            group: group,
            defaults: common.merging([idKey: value, "editable": "true", "error": forbidden, "ouId": ""]) { _, new in
                new
            },
            controls: [sourceControl, stateControl(["data", "loading", "empty", "error"])]
                + [StoryControl(name: "editable", kind: .bool)]
                + textControls
                + [StoryControl(name: idKey, kind: .text)]
                + [StoryControl(name: "ouId", kind: .text)]
                + [errorControl],
            stories: states(["data", "loading", "empty", "error"]),
            isTall: true
        ) { values in AdminSnippets.membership(name: name, idKey: idKey, values: values) }
    }
}

extension PropValues {
    /// `nil` for an empty value, so a blank title falls back to the SDK's translated default.
    func optional(_ key: String) -> String? {
        let value = text(key)
        return value.isEmpty ? nil : value
    }

    var isLive: Bool { self["source"] == "live" }
}
