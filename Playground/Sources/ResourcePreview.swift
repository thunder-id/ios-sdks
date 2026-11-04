// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID
import ThunderIDSwiftUI

/// Renders a project, organization unit, sharing or device grant story.
struct ResourcePreview: View {
    @EnvironmentObject private var state: ThunderIDState
    let id: String
    let values: PropValues
    let onEvent: (String) -> Void

    var body: some View {
        if values.isLive && !state.isSignedIn {
            PreviewHint(text: "Sign in to load live data. These components use the signed-in user's token.")
        } else if values.isLive, let missing = missingId {
            PreviewHint(text: "Set \(missing) to load it from the server.")
        } else if id.hasPrefix("project") {
            ProjectPreview(id: id, values: values, onEvent: onEvent)
        } else if id.hasPrefix("organizationUnit") {
            OrganizationUnitPreview(id: id, values: values, onEvent: onEvent)
        } else if id == "sharingPolicies" {
            SharingPreview(values: values, onEvent: onEvent)
        } else {
            DeviceGrantPreview(values: values, onEvent: onEvent)
        }
    }

    private var missingId: String? {
        ["projectId", "organizationUnitId", "resourceId"].first { values[$0] != nil && values.text($0).isEmpty }
    }
}

extension PropValues {
    var isCustom: Bool { self["render"] == "custom" }
}

// MARK: - Projects

private struct ProjectPreview: View {
    @EnvironmentObject private var state: ThunderIDState
    let id: String
    let values: PropValues
    let onEvent: (String) -> Void
    @State private var current: String? = ResourceSamples.projects.first?.id

    var body: some View {
        switch id {
        case "projectList": list
        case "projectCreate": create
        case "projectDetails": details
        default: switcher
        }
    }

    @ViewBuilder private var list: some View {
        let onSelect: (Project) -> Void = { onEvent("onSelect \($0.handle)") }
        switch (values.isLive, values.isCustom) {
        case (true, true): ProjectList(onSelect: onSelect) { CustomRows(list: $0, title: \.displayName) }
        case (true, false): ProjectList(onSelect: onSelect)
        case (false, true):
            BaseProjectList(projects: ResourceSamples.projects, onSelect: onSelect) {
                CustomRows(list: $0, title: \.displayName)
            }
        case (false, false):
            BaseProjectList(projects: ResourceSamples.projects, onPageChange: { _ in }, onSelect: onSelect)
        }
    }

    @ViewBuilder private var create: some View {
        let onCreated: (Project) -> Void = { onEvent("onCreated \($0.handle)") }
        switch (values.isLive, values.isCustom) {
        case (true, true): ProjectCreate(onCreated: onCreated) { CustomProjectForm(form: $0) }
        case (true, false): ProjectCreate(onCancel: cancelled, onCreated: onCreated)
        case (false, true): BaseProjectCreate(onSubmit: submitted) { CustomProjectForm(form: $0) }
        case (false, false): BaseProjectCreate(onCancel: cancelled, onSubmit: submitted)
        }
    }

    @ViewBuilder private var details: some View {
        if values.isLive {
            if values.isCustom {
                ProjectDetails(projectId: values.text("projectId"), deletable: values.flag("deletable")) {
                    CustomProjectCard(details: $0)
                }
            } else {
                ProjectDetails(
                    projectId: values.text("projectId"),
                    editable: values.flag("editable"),
                    deletable: values.flag("deletable"),
                    onDeleted: deleted
                )
            }
        } else if values.isCustom {
            BaseProjectDetails(project: ResourceSamples.projects[1], onDelete: deleted) {
                CustomProjectCard(details: $0)
            }
        } else {
            BaseProjectDetails(
                project: ResourceSamples.projects[1],
                onUpdate: values.flag("editable") ? { onEvent("onUpdate \($0.displayName)") } : nil,
                onDelete: values.flag("deletable") ? { onEvent("onDelete") } : nil
            )
        }
    }

    @ViewBuilder private var switcher: some View {
        let onSelect: (Project) -> Void = { onEvent("onSelect \($0.handle)") }
        switch (values.isLive, values.isCustom) {
        case (true, true): ProjectSwitcher(onSelect: onSelect) { ProjectPicker(switcher: $0) }
        case (true, false): ProjectSwitcher(onSelect: onSelect)
        case (false, true):
            BaseProjectSwitcher(projects: ResourceSamples.projects, currentId: current, onSelect: sampleSelect) {
                ProjectPicker(switcher: $0)
            }
        case (false, false):
            BaseProjectSwitcher(
                projects: ResourceSamples.projects,
                currentId: current,
                onClear: { current = nil },
                onSelect: sampleSelect
            )
        }
    }

    private func cancelled() { onEvent("onCancel") }

    private func deleted() { onEvent("onDelete") }

    private func submitted(_ request: CreateProjectRequest) { onEvent("onSubmit \(request.handle)") }

    private func sampleSelect(_ project: Project) {
        current = project.id
        onEvent("onSelect \(project.handle)")
    }
}

// MARK: - Organization units

private struct OrganizationUnitPreview: View {
    let id: String
    let values: PropValues
    let onEvent: (String) -> Void

    private var parentId: String? { values.optional("parentId") }

    private func cancelled() { onEvent("onCancel") }

    private func submitted(_ request: OrganizationUnitRequest) { onEvent("onSubmit \(request.handle)") }

    var body: some View {
        switch id {
        case "organizationUnitList": list
        case "organizationUnitCreate": create
        default: details
        }
    }

    @ViewBuilder private var list: some View {
        let onSelect: (OrganizationUnitSummary) -> Void = { onEvent("onSelect \($0.handle)") }
        switch (values.isLive, values.isCustom) {
        case (true, true):
            OrganizationUnitList(parentId: parentId, onSelect: onSelect) { CustomRows(list: $0, title: \.name) }
        case (true, false): OrganizationUnitList(parentId: parentId, onSelect: onSelect)
        case (false, true):
            BaseOrganizationUnitList(units: ResourceSamples.units, onSelect: onSelect) {
                CustomRows(list: $0, title: \.name)
            }
        case (false, false): BaseOrganizationUnitList(units: ResourceSamples.units, onSelect: onSelect)
        }
    }

    @ViewBuilder private var create: some View {
        let parents = ResourceSamples.units.map { AdminOption(label: $0.name, value: $0.id) }
        switch (values.isLive, values.isCustom) {
        case (true, true): OrganizationUnitCreate(parentId: parentId) { CustomUnitForm(form: $0) }
        case (true, false):
            OrganizationUnitCreate(parentId: parentId, onCancel: cancelled) {
                onEvent("onCreated \($0.handle)")
            }
        case (false, true):
            BaseOrganizationUnitCreate(parentId: parentId, parents: parents, onSubmit: submitted) {
                CustomUnitForm(form: $0)
            }
        case (false, false):
            BaseOrganizationUnitCreate(parentId: parentId, parents: parents, onSubmit: submitted)
        }
    }

    @ViewBuilder private var details: some View {
        if values.isLive {
            if values.isCustom {
                OrganizationUnitDetails(organizationUnitId: values.text("organizationUnitId")) {
                    CustomUnitCard(details: $0)
                }
            } else {
                OrganizationUnitDetails(
                    organizationUnitId: values.text("organizationUnitId"),
                    editable: values.flag("editable"),
                    deletable: values.flag("deletable"),
                    onSelectChild: { onEvent("onSelectChild \($0.handle)") },
                    onDeleted: { onEvent("onDeleted") }
                )
            }
        } else if values.isCustom {
            BaseOrganizationUnitDetails(unit: ResourceSamples.unit, children: ResourceSamples.units) {
                CustomUnitCard(details: $0)
            }
        } else {
            BaseOrganizationUnitDetails(
                unit: ResourceSamples.unit,
                children: ResourceSamples.units,
                users: ResourceSamples.unitUsers,
                groups: ResourceSamples.unitGroups,
                roles: ResourceSamples.unitRoles,
                onSelectChild: { onEvent("onSelectChild \($0.handle)") },
                onUpdate: values.flag("editable") ? { onEvent("onUpdate \($0.name)") } : nil,
                onDelete: values.flag("deletable") ? { onEvent("onDelete") } : nil
            )
        }
    }
}

// MARK: - Sharing and device grant

private struct SharingPreview: View {
    let values: PropValues
    let onEvent: (String) -> Void

    private var type: SharingResourceType { SharingResourceType(rawValue: values.text("resourceType")) ?? .role }

    private func deleted(_ policy: SharingPolicy) { onEvent("onDelete \(policy.id ?? "")") }

    var body: some View {
        if values.isLive {
            if values.isCustom {
                SharingPolicies(
                    resourceType: type,
                    resourceId: values.text("resourceId"),
                    ouId: values.optional("ouId"),
                    editable: values.flag("editable")
                ) { CustomPolicyRows(sharing: $0) }
            } else {
                SharingPolicies(
                    resourceType: type,
                    resourceId: values.text("resourceId"),
                    ouId: values.optional("ouId"),
                    editable: values.flag("editable")
                )
            }
        } else if values.isCustom {
            BaseSharingPolicies(policies: ResourceSamples.policies, onDelete: deleted) {
                CustomPolicyRows(sharing: $0)
            }
        } else {
            let editable = values.flag("editable")
            BaseSharingPolicies(
                policies: ResourceSamples.policies,
                overlay: ResourceSamples.overlay,
                onCreate: editable ? { _ in onEvent("onCreate") } : nil,
                onUpdate: editable ? { policy, _ in onEvent("onUpdate \(policy.id ?? "")") } : nil,
                onDelete: editable ? { onEvent("onDelete \($0.id ?? "")") } : nil
            )
        }
    }
}

private struct DeviceGrantPreview: View {
    let values: PropValues
    let onEvent: (String) -> Void
    @State private var result: DeviceGrantResult?

    var body: some View {
        if values.isLive {
            if values.isCustom {
                DeviceGrant(userCode: values.optional("userCode"), onComplete: complete) { CustomCodeEntry(grant: $0) }
            } else {
                DeviceGrant(userCode: values.optional("userCode"), onComplete: complete) { onEvent("onError \($0)") }
            }
        } else if values.isCustom {
            BaseDeviceGrant(inputs: ResourceSamples.codeInputs, result: result, onSubmit: sampleSubmit) {
                CustomCodeEntry(grant: $0)
            }
        } else {
            BaseDeviceGrant(
                inputs: ResourceSamples.codeInputs,
                initialValues: values.optional("userCode").map { ["user_code": $0] } ?? [:],
                result: result,
                onSubmit: sampleSubmit
            )
        }
    }

    private func complete(_ outcome: DeviceGrantResult) {
        onEvent("onComplete \(outcome.rawValue)")
    }

    /// The sample approves any code, so the outcome card shows.
    private func sampleSubmit(_ actionId: String?, _ inputs: [String: String]) {
        onEvent("onSubmit \(inputs["user_code"] ?? "")")
        result = (inputs["user_code"] ?? "").isEmpty ? .denied : .approved
    }
}
