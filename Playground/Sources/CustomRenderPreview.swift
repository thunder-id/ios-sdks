// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID
import ThunderIDSwiftUI

/// Renders the custom rendering stories: components whose `content` closure draws the UI.
struct CustomRenderPreview: View {
    @EnvironmentObject private var state: ThunderIDState
    let id: String
    let values: PropValues
    let onEvent: (String) -> Void

    var body: some View {
        if id == "customVerifyAttribute" {
            CustomVerifyAttributeStory(values: values, onEvent: onEvent)
        } else if values.isLive && !state.isSignedIn {
            PreviewHint(text: "Sign in to load live data. The management API uses the signed-in user's token.")
        } else {
            switch id {
            case "customUserList": CustomUserListStory(values: values, onEvent: onEvent)
            case "customGroupCreate": groupCreate
            case "customApplicationDetails": CustomApplicationDetailsStory(values: values, onEvent: onEvent)
            default: userDetails
            }
        }
    }

    @ViewBuilder private var groupCreate: some View {
        if values.isLive {
            GroupCreate(
                onCreated: { group in onEvent("onCreated \(group.id)") },
                content: { GroupForm(form: $0) }
            )
        } else {
            BaseGroupCreate(
                onSubmit: { submission in onEvent("onSubmit \(submission.name)") },
                content: { GroupForm(form: $0) }
            )
        }
    }

    @ViewBuilder private var userDetails: some View {
        if values.isLive {
            if values.text("userId").isEmpty {
                PreviewHint(text: "Set userId, or run the Management checks to find one on the server.")
            } else {
                UserDetails(
                    userId: values.text("userId"),
                    deletable: true,
                    onDeleted: { onEvent("onDeleted") },
                    content: { UserCard(details: $0) }
                )
            }
        } else {
            BaseUserDetails(
                user: AdminSamples.users.first,
                groups: AdminSamples.userGroups,
                onDelete: { onEvent("onDelete") },
                content: { UserCard(details: $0) }
            )
        }
    }
}

/// Pages the sample users the way an application holding the data would.
private struct CustomUserListStory: View {
    let values: PropValues
    let onEvent: (String) -> Void
    @State private var offset = 0
    @State private var selected: String?

    var body: some View {
        if values.isLive {
            UserList(
                limit: values.limit,
                onSelect: { onEvent("onSelect \($0.id)") },
                content: { UserRows(list: $0) }
            )
        } else {
            let users = AdminSamples.users
            BaseUserList(
                users: Array(users.dropFirst(offset).prefix(values.limit)),
                limit: values.limit,
                offset: offset,
                totalResults: users.count,
                selectedUserId: selected,
                onPageChange: { next in
                    offset = next
                    onEvent("onPageChange \(next)")
                },
                onSelect: { user in
                    selected = user.id
                    onEvent("onSelect \(user.id)")
                },
                content: { UserRows(list: $0) }
            )
        }
    }
}

/// The list state drawn as cards with a pager: no table, only the SDK's rows and callbacks.
private struct UserRows: View {
    let list: AdminListState<ManagedUser>

    var body: some View {
        VStack(spacing: 8) {
            if list.isLoading && list.rows.isEmpty {
                ProgressView()
            }
            if let error = list.error {
                Text(error).foregroundColor(.red)
            }
            ForEach(list.rows, id: \.id) { user in
                row(user)
            }
            pager
        }
    }

    private func row(_ user: ManagedUser) -> some View {
        let isSelected = user.id == list.selectedId
        return HStack(spacing: 12) {
            Circle()
                .fill(Palette.primary.opacity(0.25))
                .frame(width: 34, height: 34)
                .overlay(Text(String(user.resolvedName.prefix(1))).font(.system(size: 14, weight: .semibold)))
            VStack(alignment: .leading, spacing: 2) {
                Text(user.resolvedName).font(.system(size: 15, weight: .medium))
                Text("\(user.type) · \(user.ouHandle ?? user.ouId)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundColor(Palette.primary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.text(isSelected ? 0.08 : 0.04)))
        .contentShape(Rectangle())
        .onTapGesture { list.onSelect?(user) }
    }

    @ViewBuilder private var pager: some View {
        if let change = list.onPageChange, list.totalResults > list.limit {
            HStack {
                Button("Previous") { change(max(0, list.offset - list.limit)) }
                    .disabled(list.offset == 0)
                Spacer()
                Text("\(list.offset + 1)–\(min(list.offset + list.limit, list.totalResults)) of \(list.totalResults)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Next") { change(list.offset + list.limit) }
                    .disabled(list.offset + list.limit >= list.totalResults)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.top, 4)
        }
    }
}

/// The group form state drawn with plain SwiftUI fields bound to the SDK's bindings.
private struct GroupForm: View {
    let form: NamedResourceFormState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New group").font(.system(size: 20, weight: .semibold))
            TextField("Name", text: form.name)
                .textFieldStyle(.roundedBorder)
            TextField("Description", text: form.description, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            if let error = form.error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }
            HStack {
                if let cancel = form.onCancel {
                    Button("Cancel", action: cancel)
                }
                Spacer()
                Button(form.isSubmitting ? "Creating…" : "Create group", action: form.submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(!form.isValid || form.isSubmitting)
            }
        }
    }
}

/// The user details state drawn as a profile card.
private struct UserCard: View {
    let details: UserDetailsState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if details.isLoading && details.user == nil {
                ProgressView()
            } else {
                Text(details.displayName).font(.system(size: 22, weight: .semibold))
                if let user = details.user {
                    Text("\(user.type) · \(user.ouHandle ?? user.ouId)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                ForEach(details.attributes.keys.sorted(), id: \.self) { name in
                    HStack {
                        Text(name).foregroundColor(.secondary)
                        Spacer()
                        Text(stringValue(details.attributes[name]))
                    }
                    .font(.system(size: 14))
                }
                Text(details.groups.map(\.name).joined(separator: " · "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.primary)
                if let delete = details.onDelete {
                    Button("Delete user", role: .destructive, action: delete)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.text(0.05)))
    }

    private func stringValue(_ value: AnyCodable?) -> String {
        guard let value else { return "" }
        return (value.value as? String) ?? "\(value.value)"
    }
}

/// Verifies an attribute of the signed-in user with the step drawn by the app. Both variants send a code.
private struct CustomVerifyAttributeStory: View {
    @EnvironmentObject private var state: ThunderIDState
    let values: PropValues
    let onEvent: (String) -> Void

    var body: some View {
        let attribute = values.text("attribute")
        if !state.isSignedIn {
            PreviewHint(text: "Sign in first. Showing this story sends a code or a link to the attribute.")
        } else if values.text("variant") == "base" {
            BaseVerifyAttribute(
                attribute: attribute,
                onComplete: { onEvent("onComplete") },
                onDone: { onEvent("onDone") },
                onCancel: { onEvent("onCancel") },
                onError: { onEvent("onError \($0.localizedDescription)") },
                content: { VerificationCard(step: $0) }
            )
            .id("base|\(attribute)")
        } else {
            VerifyAttribute(
                attribute: attribute,
                onComplete: { onEvent("onComplete") },
                onDone: { onEvent("onDone") },
                onCancel: { onEvent("onCancel") },
                onError: { onEvent("onError \($0.localizedDescription)") },
                content: { VerificationCard(step: $0) }
            )
            .id("connected|\(attribute)")
        }
    }
}

/// A verification step drawn as a card: plain fields and buttons bound to the SDK's state.
private struct VerificationCard: View {
    @ObservedObject var step: VerifyAttributeState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch step.phase {
            case .loading:
                ProgressView()
            case .active:
                activeStep
            case .complete:
                Label(step.successMessage, systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
            case .failed:
                Text(step.error ?? "").foregroundColor(.red)
            }
            if let cancel = step.onCancel {
                Button(step.phase == .active || step.phase == .loading ? "Cancel" : "Close", action: cancel)
                    .disabled(step.isLoading)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.text(0.05)))
    }

    @ViewBuilder private var activeStep: some View {
        Text(step.title).font(.system(size: 20, weight: .semibold))
        Text(step.subtitle)
            .font(.system(size: 14))
            .foregroundColor(.secondary)
        if let sentTo = step.destinationMessage {
            Text(sentTo)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        if let error = step.error {
            Text(error)
                .font(.system(size: 13))
                .foregroundColor(.red)
        }
        ForEach(StepPart.parts(of: step), id: \.id) { part in
            partView(part)
        }
        if step.isAwaitingLink {
            Button("I opened the link", action: step.done)
                .buttonStyle(.borderedProminent)
                .disabled(step.isLoading)
        }
    }

    @ViewBuilder private func partView(_ part: StepPart) -> some View {
        switch part.kind {
        case .field:
            VStack(alignment: .leading, spacing: 4) {
                TextField(step.text(part.label) ?? "Code", text: step.binding(for: part.id))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("thunderid-field-\(part.id)")
                if let message = step.fieldErrors[part.id] {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            }
        case .submit:
            Button(step.text(part.label) ?? "Verify") { step.submit(actionId: part.id) }
                .accessibilityIdentifier("thunderid-action-\(part.id)")
                .buttonStyle(.borderedProminent)
                .disabled(step.isLoading)
        case .resend:
            Button(step.text(part.label) ?? "Send a new code") { step.resend(actionId: part.id) }
                .accessibilityIdentifier("thunderid-action-\(part.id)")
                .disabled(step.isLoading)
        }
    }
}

/// A field or action of the step, read from its components, or from its inputs and actions when it has none.
private struct StepPart {
    enum Kind { case field, submit, resend }

    let id: String
    let kind: Kind
    let label: String?

    @MainActor
    static func parts(of step: VerifyAttributeState) -> [StepPart] {
        guard !step.components.isEmpty else {
            return step.inputs.map { StepPart(id: $0.name, kind: .field, label: nil) }
                + step.actions.map { StepPart(id: $0.id, kind: .submit, label: $0.label) }
        }
        return flatten(step.components)
    }

    private static func flatten(_ components: [FlowComponent]) -> [StepPart] {
        components.flatMap { component -> [StepPart] in
            let id = component.id ?? component.ref ?? ""
            switch component.type {
            case "BLOCK": return flatten(component.components ?? [])
            case "ACTION": return [StepPart(id: id, kind: .submit, label: component.label)]
            case "RESEND": return [StepPart(id: id, kind: .resend, label: component.label)]
            case let type? where type.hasSuffix("_INPUT"):
                return [StepPart(id: component.ref ?? component.id ?? "", kind: .field, label: component.label)]
            default: return []
            }
        }
    }
}
