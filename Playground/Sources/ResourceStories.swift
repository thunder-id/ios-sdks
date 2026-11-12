// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Stories for the project, organization unit, sharing and device grant components. Each has a `sample`
/// source, which renders the `Base*` view with sample records, a `live` source, which renders the
/// connected view against the server with the signed-in user's token, and a Custom rendering story that
/// draws the component's state with plain SwiftUI through its `content` closure.
extension ExplorerCatalog {
    static func resources(ids: AdminStoryIds) -> [ComponentSpec] {
        [
            resource("projectList", "ProjectList", group: "Projects"),
            resource("projectCreate", "ProjectCreate", group: "Projects"),
            resource("projectDetails", "ProjectDetails", group: "Projects", extra: detailControls("projectId")),
            resource("projectSwitcher", "ProjectSwitcher", group: "Projects"),
            resource(
                "organizationUnitList",
                "OrganizationUnitList",
                group: "Organization units",
                extra: [(StoryControl(name: "parentId", kind: .text), "")]
            ),
            resource(
                "organizationUnitCreate",
                "OrganizationUnitCreate",
                group: "Organization units",
                extra: [(StoryControl(name: "parentId", kind: .text), "")]
            ),
            resource(
                "organizationUnitDetails",
                "OrganizationUnitDetails",
                group: "Organization units",
                extra: detailControls("organizationUnitId")
            ),
            resource(
                "sharingPolicies",
                "SharingPolicies",
                group: "Sharing",
                extra: [
                    (
                        StoryControl(name: "resourceType", kind: .options(["role", "user", "application", "flow"])),
                        "role"
                    ),
                    (StoryControl(name: "resourceId", kind: .text), ids.roleId),
                    (StoryControl(name: "ouId", kind: .text), ""),
                    (StoryControl(name: "editable", kind: .bool), "true")
                ]
            ),
            resource(
                "sharedFlowList",
                "SharedFlowList",
                group: "Sharing",
                extra: [
                    (StoryControl(name: "ouId", kind: .text), ""),
                    (StoryControl(name: "ownership", kind: .options(["shared", "owned", "all"])), "shared")
                ]
            ),
            resource(
                "flowVariablesForm",
                "FlowVariablesForm",
                group: "Sharing",
                extra: [
                    (StoryControl(name: "flowId", kind: .text), ""),
                    (StoryControl(name: "ouId", kind: .text), ""),
                    (StoryControl(name: "readOnly", kind: .bool), "false")
                ]
            ),
            resource(
                "deviceGrant",
                "DeviceGrant",
                group: "Device grant",
                extra: [(StoryControl(name: "userCode", kind: .text), "")]
            )
        ]
    }

    private static func detailControls(_ idKey: String) -> [(StoryControl, String)] {
        [
            (StoryControl(name: idKey, kind: .text), ""),
            (StoryControl(name: "editable", kind: .bool), "true"),
            (StoryControl(name: "deletable", kind: .bool), "false")
        ]
    }

    private static func resource(
        _ id: String,
        _ name: String,
        group: String,
        extra: [(StoryControl, String)] = []
    ) -> ComponentSpec {
        var defaults: PropValues = ["source": "sample", "render": "built-in"]
        for (control, value) in extra { defaults[control.name] = value }
        return ComponentSpec(
            id: id,
            name: name,
            group: group,
            defaults: defaults,
            controls: [
                StoryControl(name: "source", kind: .options(["sample", "live"])),
                StoryControl(name: "render", kind: .options(["built-in", "custom"]))
            ] + extra.map(\.0),
            stories: [
                Story(id: "sample", name: "Sample", preset: ["source": "sample", "render": "built-in"]),
                Story(id: "live", name: "Live", preset: ["source": "live", "render": "built-in"]),
                Story(id: "custom", name: "Custom rendering", preset: ["source": "sample", "render": "custom"])
            ],
            isTall: true
        ) { values in resourceSnippet(name: name, values: values) }
    }

    private static func resourceSnippet(name: String, values: PropValues) -> String {
        let live = values.isLive
        let head = live ? "\(name)(\(liveArguments(name: name, values: values)))" : "Base\(name)(/* sample data */)"
        guard values.text("render") == "custom" else { return head }
        return """
        \(head) { state in
            // Draw `state` with any SwiftUI: \(customHint(name))
        }
        """
    }

    private static func liveArguments(name: String, values: PropValues) -> String {
        switch name {
        case "ProjectDetails": return "projectId: \(quote(values.text("projectId"))), editable: true"
        case "OrganizationUnitDetails": return "organizationUnitId: \(quote(values.text("organizationUnitId")))"
        case "OrganizationUnitList", "OrganizationUnitCreate":
            return values.text("parentId").isEmpty ? "" : "parentId: \(quote(values.text("parentId")))"
        case "SharingPolicies":
            return "resourceType: .\(values.text("resourceType")), resourceId: \(quote(values.text("resourceId"))), "
                + "editable: \(values.text("editable"))"
        case "SharedFlowList":
            return "ouId: \(quote(values.text("ouId"))), ownership: .\(values.text("ownership"))"
        case "FlowVariablesForm":
            return "flowId: \(quote(values.text("flowId"))), ouId: \(quote(values.text("ouId")))"
        case "DeviceGrant":
            return values.text("userCode").isEmpty ? "" : "userCode: \(quote(values.text("userCode")))"
        default: return ""
        }
    }

    private static func customHint(_ name: String) -> String {
        switch name {
        case "ProjectSwitcher": return "a Picker over state.projects that calls state.onSelect"
        case "ProjectCreate", "OrganizationUnitCreate": return "bind TextFields to the form, then state.submit()"
        case "SharingPolicies": return "rows from state.policies with state.scope(of:), state.onDelete when editable"
        case "SharedFlowList": return "rows from state.rows, each calling state.onSelect"
        case "FlowVariablesForm": return "a control per state.variables, state.setValue(_:for:), then state.submit"
        case "DeviceGrant": return "a code field from state.value(for: \"user_code\"), then state.submit(nil)"
        default: return "rows, record and the actions the app allowed"
        }
    }
}
