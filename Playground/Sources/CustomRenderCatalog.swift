// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Stories that replace a component's default UI through its `content` closure. The closure gets the
/// component's state (rows and paging, bindings and submit, the loaded record, or a verification step),
/// so any SwiftUI layout can draw it.
extension ExplorerCatalog {
    static func customRender(ids: AdminStoryIds) -> [ComponentSpec] {
        [
            customUserList,
            customGroupCreate,
            customUserDetails(userId: ids.userId),
            customApplicationDetails(applicationId: ids.applicationId),
            customVerifyAttribute
        ]
    }

    private static let customSource = StoryControl(name: "source", kind: .options(["sample", "live"]))

    private static func customStories(liveName: String) -> [Story] {
        [
            Story(id: "sample", name: "Sample", preset: ["source": "sample"]),
            Story(id: "live", name: liveName, preset: ["source": "live"])
        ]
    }

    private static let customUserList = ComponentSpec(
        id: "customUserList",
        name: "UserList → custom rows",
        group: "Custom rendering",
        defaults: ["source": "sample", "limit": "2"],
        controls: [customSource, StoryControl(name: "limit", kind: .options(["2", "5", "20"]))],
        stories: customStories(liveName: "Live"),
        isTall: true
    ) { values in
        let head = values.isLive
            ? "UserList(limit: \(values.text("limit")))"
            : "BaseUserList(users: page, totalResults: total)"
        return """
        \(head) { list in
            VStack(spacing: 8) {
                ForEach(list.rows) { user in
                    UserRow(user: user, isSelected: user.id == list.selectedId)
                        .onTapGesture { list.onSelect?(user) }
                }
                HStack {
                    Button("Previous") { list.onPageChange?(max(0, list.offset - list.limit)) }
                        .disabled(list.offset == 0)
                    Spacer()
                    Text("\\(list.offset + 1)–\\(list.offset + list.rows.count) of \\(list.totalResults)")
                    Spacer()
                    Button("Next") { list.onPageChange?(list.offset + list.limit) }
                        .disabled(list.offset + list.limit >= list.totalResults)
                }
            }
        }
        """
    }

    private static let customGroupCreate = ComponentSpec(
        id: "customGroupCreate",
        name: "GroupCreate → Form",
        group: "Custom rendering",
        defaults: ["source": "sample"],
        controls: [customSource],
        stories: customStories(liveName: "Live (creates a group)"),
        isTall: true
    ) { values in
        let head = values.isLive
            ? "GroupCreate(onCreated: { group in /* open group.id */ })"
            : "BaseGroupCreate(onSubmit: { _ in })"
        return """
        \(head) { form in
            Form {
                TextField("Name", text: form.name)
                TextField("Description", text: form.description, axis: .vertical)
                if let error = form.error { Text(error).foregroundColor(.red) }
                Button("Create group", action: form.submit)
                    .disabled(!form.isValid || form.isSubmitting)
            }
        }
        """
    }

    private static func customUserDetails(userId: String) -> ComponentSpec {
        ComponentSpec(
            id: "customUserDetails",
            name: "UserDetails → card",
            group: "Custom rendering",
            defaults: ["source": "sample", "userId": userId],
            controls: [customSource, StoryControl(name: "userId", kind: .text)],
            stories: customStories(liveName: "Live"),
            isTall: true
        ) { values in
            let head = values.isLive
                ? "UserDetails(userId: \(quote(values.text("userId"))), deletable: true)"
                : "BaseUserDetails(user: user, groups: groups, onDelete: {})"
            return """
            \(head) { details in
                VStack(alignment: .leading, spacing: 12) {
                    Text(details.displayName).font(.title2.bold())
                    ForEach(details.attributes.keys.sorted(), id: \\.self) { name in
                        LabeledContent(name, value: "\\(details.attributes[name]?.value ?? "")")
                    }
                    if let delete = details.onDelete {
                        Button("Delete", role: .destructive, action: delete)
                    }
                }
            }
            """
        }
    }

    private static let customVerifyAttribute = ComponentSpec(
        id: "customVerifyAttribute",
        name: "VerifyAttribute → code card",
        group: "Custom rendering",
        defaults: ["variant": "connected", "attribute": "email"],
        controls: [
            StoryControl(name: "variant", kind: .options(["connected", "base"])),
            StoryControl(name: "attribute", kind: .text)
        ],
        stories: [
            Story(id: "connected", name: "Live (sends a code)", preset: ["variant": "connected"]),
            Story(id: "base", name: "Base, live (sends a code)", preset: ["variant": "base"])
        ],
        isTall: true
    ) { values in
        let name = values.text("variant") == "base" ? "BaseVerifyAttribute" : "VerifyAttribute"
        return """
        \(name)(attribute: \(quote(values.text("attribute"))), onCancel: { /* close */ }) { step in
            // step.components carries the server's layout, labels and RESEND; inputs and actions are the flat form.
            VStack(alignment: .leading, spacing: 12) {
                Text(step.title).font(.title2.bold())
                Text(step.subtitle)
                if let error = step.error { Text(error).foregroundColor(.red) }
                ForEach(step.inputs) { input in
                    TextField(input.name, text: step.binding(for: input.name))
                }
                ForEach(step.actions, id: \\.id) { action in
                    Button(step.text(action.label) ?? "Verify") { step.submit(actionId: action.id) }
                        .disabled(step.isLoading)
                }
                if step.phase == .complete { Label(step.successMessage, systemImage: "checkmark.seal") }
                if let cancel = step.onCancel { Button("Cancel", action: cancel) }
            }
        }
        .id(\(quote(values.text("attribute"))))
        """
    }
}
