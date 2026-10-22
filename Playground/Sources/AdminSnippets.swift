// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// SwiftUI snippets for the admin stories, generated from the current props.
enum AdminSnippets {
    static func list(name: String, item: String, values: PropValues) -> String {
        let singular = String(item.dropLast())
        if values.isLive {
            return call(name, ["limit: \(values.text("limit"))"] + texts(values)
                + ["onSelect: { \(singular) in /* open \(singular).id */ }"])
        }
        return call("Base\(name)", [
            "\(item): \(values.text("state") == "empty" ? "[]" : item)"
        ] + state(values) + texts(values) + ["onSelect: { \(singular) in /* open \(singular).id */ }"])
    }

    static func detail(name: String, idKey: String, values: PropValues) -> String {
        let id = ExplorerCatalog.quote(values.text(idKey))
        if name == "RolePermissions" {
            return values.isLive
                ? call(name, ["roleId: \(id)"] + texts(values))
                : call("BaseRolePermissions", ["permissions: role.permissions", "resourceServerNames: names"]
                    + state(values) + texts(values))
        }
        let deletable = values.flag("deletable")
        if values.isLive {
            let deletion = deletable ? ["deletable: true", "onDeleted: { /* deleted */ }"] : []
            return call(name, ["\(idKey): \(id)"] + deletion)
        }
        let record = name == "UserDetails"
            ? ["user: user", "groups: groups"]
            : ["agent: agent", "groups: groups", "roles: roles"]
        return call("Base\(name)", record + state(values)
            + (deletable ? ["onDelete: { /* delete */ }"] : []))
    }

    static func create(name: String, values: PropValues) -> String {
        if values.isLive {
            let ouId = values.optional("ouId").map { ["ouId: \(ExplorerCatalog.quote($0))"] } ?? []
            return call(name, ouId + texts(values) + ["onCancel: { /* close */ }"])
                + " { created in\n    // created.id\n}"
        }
        var args: [String] = []
        if name == "UserCreate" { args.append("userTypes: userTypes") }
        if name == "AgentCreate" { args.append("agentTypes: agentTypes") }
        if values.text("state") == "error" { args.append("error: \(ExplorerCatalog.quote(values.text("error")))") }
        if values.text("state") == "submitting" { args.append("isSubmitting: true") }
        return call("Base\(name)", args + texts(values) + ["onCancel: { /* close */ }"])
            + " { submission in\n    // submission.name\n}"
    }

    static func membership(name: String, idKey: String, values: PropValues) -> String {
        let isGroup = name == "GroupMembers"
        if values.isLive {
            return call(name, ["\(idKey): \(ExplorerCatalog.quote(values.text(idKey)))"]
                + (values.flag("editable") ? ["editable: true"] : []) + texts(values))
        }
        let rows = isGroup ? "members" : "assignments"
        var args = ["\(rows): \(values.text("state") == "empty" ? "[]" : rows)"]
        if values.flag("editable") {
            args += isGroup ? groupEditing : roleEditing
        }
        return call("Base\(name)", args + state(values) + texts(values))
    }

    // MARK: - Helpers

    private static let groupEditing = [
        "candidates: [.user: users, .agent: agents]",
        "onAdd: { member in /* add */ }",
        "onRemove: { member in /* remove */ }"
    ]

    private static let roleEditing = [
        "candidates: [.user: users, .group: groups, .agent: agents]",
        "onAssign: { assignee in /* assign */ }",
        "onUnassign: { assignment in /* unassign */ }"
    ]

    private static func state(_ values: PropValues) -> [String] {
        switch values.text("state") {
        case "loading": return ["isLoading: true"]
        case "error": return ["error: \(ExplorerCatalog.quote(values.text("error")))"]
        default: return []
        }
    }

    private static func texts(_ values: PropValues) -> [String] {
        ["title", "description"].compactMap { key in
            values.optional(key).map { "\(key): \(ExplorerCatalog.quote($0))" }
        }
    }

    private static func call(_ name: String, _ args: [String]) -> String {
        args.isEmpty ? "\(name)()" : "\(name)(\n    " + args.joined(separator: ",\n    ") + "\n)"
    }
}
