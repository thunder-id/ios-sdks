// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID
import ThunderIDSwiftUI

/// Sample records for the project, organization unit, sharing and device grant stories, decoded from
/// JSON shaped like the API's.
enum ResourceSamples {
    static let projects: [Project] = decode("""
    [
      {"id": "prj-default", "handle": "default", "displayName": "Default", "createdAt": "2026-01-05T09:00:00Z"},
      {"id": "prj-shop", "handle": "online-shop", "displayName": "Online shop",
       "description": "Customer accounts for the storefront", "createdAt": "2026-03-14T16:20:00Z"},
      {"id": "prj-partners", "handle": "partners", "displayName": "Partner portal"}
    ]
    """)

    static let units: [OrganizationUnitSummary] = decode("""
    [
      {"id": "ou-eng", "handle": "engineering", "name": "Engineering", "description": "Product teams"},
      {"id": "ou-sales", "handle": "sales", "name": "Sales"},
      {"id": "ou-support", "handle": "support", "name": "Support", "description": "Customer care"}
    ]
    """)

    static let unit: OrganizationUnit = decode("""
    {"id": "ou-acme", "handle": "acme", "name": "Acme", "parent": "ou-shop",
     "description": "The Acme business unit"}
    """)

    static let unitUsers: [OrganizationUnitUser] = decode("""
    [{"id": "usr-liam", "display": "Liam Chen", "isOwned": true}, {"id": "usr-ana", "display": "Ana Silva"}]
    """)

    static let unitGroups: [OrganizationUnitGroup] = decode(#"[{"id": "grp-eng", "name": "Engineering"}]"#)

    static let unitRoles: [OrganizationUnitRole] = decode(#"[{"id": "role-viewer", "name": "Viewer"}]"#)

    static let policies: [SharingPolicy] = decode("""
    [
      {"id": "pol-all", "initiatingOuId": "ou-acme", "stage": "share", "version": 3,
       "childUnits": {"mode": "all", "excludedOuIds": ["ou-sales"]}},
      {"id": "pol-picked", "initiatingOuId": "ou-acme", "stage": "share", "version": 1,
       "childUnits": {"mode": "selected", "units": [{"ouId": "ou-eng", "reach": "subtree"}]},
       "otherTreeRoots": {"mode": "selected", "units": [{"ouId": "ou-partners"}]}},
      {"id": "pol-reshare", "stage": "reshare", "isReadOnly": true,
       "childUnits": {"mode": "selected", "units": [{"ouId": "ou-support", "reach": "unit"}]}}
    ]
    """)

    static let overlay: ResolvedOverlay = decode("""
    {"ouId": "ou-eng", "isOwnedByOU": false, "visible": true, "policyIds": ["pol-picked"],
     "rules": {"locale": {"editable": true, "allowedValues": ["en-US", "fr-FR"]}, "email": {"editable": false}}}
    """)

    static let codeInputs = [FlowInput(name: "user_code", type: "TEXT_INPUT", required: true)]

    private static func decode<Value: Decodable>(_ json: String) -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: Data(json.utf8))
        } catch {
            fatalError("Invalid resource sample for \(Value.self): \(error)")
        }
    }
}

// MARK: - Custom renders

/// A custom list: tappable cards with a page summary.
struct CustomRows<Row>: View {
    let list: AdminListState<Row>
    let title: KeyPath<Row, String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if list.isLoading { ProgressView() }
            if let error = list.error {
                Text(error).foregroundColor(.red)
            }
            ForEach(Array(list.rows.enumerated()), id: \.offset) { _, row in
                Button { list.onSelect?(row) } label: {
                    Text(row[keyPath: title])
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            Text("\(list.rows.count) of \(list.totalResults)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// A custom project form: a plain Form with the handle shown as a slug.
struct CustomProjectForm: View {
    let form: ProjectFormState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Display name", text: form.displayName)
            TextField("handle", text: form.handle).font(.body.monospaced())
            TextField("What is it for?", text: form.description)
            if let error = form.error {
                Text(error).foregroundColor(.red)
            }
            Button(form.isSubmitting ? "Creating…" : "Create", action: form.submit)
                .buttonStyle(.borderedProminent)
                .disabled(!form.isValid || form.isSubmitting)
        }
        .textFieldStyle(.roundedBorder)
    }
}

/// A custom project card with a delete button when the app allows it.
struct CustomProjectCard: View {
    let details: ProjectDetailsState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(details.project?.displayName ?? "…").font(.title3.bold())
            Text(details.project?.handle ?? "").font(.caption.monospaced())
            Text(details.project?.description ?? "").foregroundColor(.secondary)
            if let error = details.error {
                Text(error).foregroundColor(.red)
            }
            if let onDelete = details.onDelete {
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
    }
}

/// A custom project switcher: a menu picker.
struct ProjectPicker: View {
    let switcher: ProjectSwitcherState

    var body: some View {
        Picker("Project", selection: selection) {
            Text("None").tag("")
            ForEach(switcher.projects, id: \.id) { project in
                Text(project.displayName).tag(project.id)
            }
        }
        .pickerStyle(.menu)
    }

    private var selection: Binding<String> {
        Binding(
            get: { switcher.currentId ?? "" },
            set: { id in
                if let project = switcher.projects.first(where: { $0.id == id }) {
                    switcher.onSelect(project)
                } else {
                    switcher.onClear?()
                }
            }
        )
    }
}

/// A custom organization unit form, with the parent as a segmented choice.
struct CustomUnitForm: View {
    let form: OrganizationUnitFormState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: form.name)
            TextField("handle", text: form.handle)
            if !form.isParentFixed {
                Picker("Parent", selection: form.parentId) {
                    Text("Root").tag("")
                    ForEach(form.parents, id: \.value) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.segmented)
            }
            Button("Create", action: form.submit)
                .buttonStyle(.borderedProminent)
                .disabled(!form.isValid)
        }
        .textFieldStyle(.roundedBorder)
    }
}

/// A custom organization unit card: the name and a count of what it holds.
struct CustomUnitCard: View {
    let details: OrganizationUnitDetailsState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(details.unit?.name ?? "…").font(.title3.bold())
            Text(details.unit?.handle ?? "").font(.caption.monospaced())
            HStack {
                Label("\(details.children.count)", systemImage: "square.stack.3d.up")
                Label("\(details.users.count)", systemImage: "person.2")
                Label("\(details.groups.count)", systemImage: "person.3")
            }
            .foregroundColor(.secondary)
        }
    }
}

/// Custom sharing rows: each policy's reach, with a swipe-free delete button when allowed.
struct CustomPolicyRows: View {
    let sharing: SharingPoliciesState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(sharing.policies.enumerated()), id: \.offset) { _, policy in
                HStack {
                    Image(systemName: policy.isReadOnly == true ? "lock" : "arrow.triangle.branch")
                    Text(sharing.scope(of: policy))
                    Spacer()
                    if let onDelete = sharing.onDelete, policy.isReadOnly != true {
                        Button(role: .destructive) { onDelete(policy) } label: { Image(systemName: "trash") }
                    }
                }
            }
        }
    }
}

/// A custom device code entry: one large monospaced field.
struct CustomCodeEntry: View {
    let grant: DeviceGrantState

    var body: some View {
        VStack(spacing: 12) {
            if let result = grant.result {
                Text(result == .approved ? "Your TV is connected" : "Not connected (\(result.rawValue))")
                    .font(.title3.bold())
            } else {
                TextField("XXXX-XXXX", text: grant.value(for: "user_code"))
                    .font(.title.monospaced())
                    .multilineTextAlignment(.center)
                if let error = grant.error {
                    Text(error).foregroundColor(.red)
                }
                Button("Connect") { grant.submit(nil) }
                    .buttonStyle(.borderedProminent)
                    .disabled(grant.isLoading)
            }
        }
    }
}
