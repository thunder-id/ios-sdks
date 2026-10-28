// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

extension ThunderIDI18n {
    /// The translated access status, or its raw value when it is one this SDK does not know.
    func accessStatusLabel(_ status: AccessStatusValue) -> String {
        switch status {
        case .active: return resolve("admin.common.status.active")
        case .locked: return resolve("admin.common.status.locked")
        case .suspended: return resolve("admin.common.status.suspended")
        default: return status.rawValue
        }
    }

    /// The translated label of an account lifecycle action.
    func lifecycleActionLabel(_ action: AccountLifecycleAction) -> String {
        resolve("admin.common.lifecycle.\(action.rawValue)")
    }

    /// The question asked before an action that needs confirmation, naming the identity.
    func lifecycleConfirmation(_ action: AccountLifecycleAction, name: String) -> String {
        resolve("admin.common.lifecycle.\(action.rawValue)_confirm", ["name": name])
    }
}

/// The operator note a suspension takes.
enum AccountLifecycleNote {
    /// Keeps a note within the server's limit while it is typed.
    static func clamped(_ text: String) -> String {
        String(text.prefix(AccountLifecycleConstants.operatorNoteMaxLength))
    }

    /// The note to send: trimmed and within the limit, or `nil` when it is blank.
    static func normalized(_ text: String) -> String? {
        let trimmed = clamped(text.trimmingCharacters(in: .whitespacesAndNewlines))
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// An identity's translated access status, as a chip. Renders nothing when the server reports none.
struct AccessStatusBadge: View {
    let i18n: ThunderIDI18n
    let status: AccessStatusValue?

    var body: some View {
        if let status {
            Text(i18n.accessStatusLabel(status))
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                .accessibilityLabel(i18n.resolve("admin.common.columns.status"))
                .accessibilityValue(i18n.accessStatusLabel(status))
                .accessibilityIdentifier("admin-access-status")
        }
    }
}

/// One button per account lifecycle action. Suspending and unsuspending ask for confirmation first;
/// unlocking is remedial and runs straight away. With `collectsOperatorNote`, a suspension also takes an
/// optional note of up to ``AccountLifecycleConstants/operatorNoteMaxLength`` characters.
struct AccountLifecycleButtons: View {
    let i18n: ThunderIDI18n
    let actions: [AccountLifecycleAction]
    var collectsOperatorNote = false
    let isRunning: Bool
    /// The identity's resolved name, used in the confirmation question.
    let name: String
    let identifier: String
    let onAction: (AccountLifecycleAction, String?) -> Void

    @State private var confirming: AccountLifecycleAction?
    @State private var operatorNote = ""

    var body: some View {
        HStack(spacing: 8) {
            ForEach(actions) { action in
                Button(role: action == .suspend ? .destructive : nil) {
                    if action.requiresConfirmation {
                        confirming = action
                    } else {
                        onAction(action, nil)
                    }
                } label: {
                    if isRunning && action == .unlock {
                        ProgressView()
                    } else {
                        Text(i18n.lifecycleActionLabel(action))
                    }
                }
                .disabled(isRunning)
                .accessibilityLabel(i18n.lifecycleActionLabel(action))
                .accessibilityIdentifier("\(identifier)-\(action.rawValue)")
            }
        }
        .alert(
            confirming.map { i18n.lifecycleConfirmation($0, name: name) } ?? "",
            isPresented: isConfirming,
            presenting: confirming
        ) { action in
            if takesNote(action) {
                TextField(
                    i18n.resolve("admin.common.lifecycle.operator_note"),
                    text: Binding(get: { operatorNote }, set: { operatorNote = AccountLifecycleNote.clamped($0) })
                )
                .accessibilityIdentifier("\(identifier)-operator-note")
            }
            Button(i18n.resolve("admin.common.actions.cancel"), role: .cancel) {}
            Button(i18n.lifecycleActionLabel(action), role: action == .suspend ? .destructive : nil) {
                onAction(action, takesNote(action) ? AccountLifecycleNote.normalized(operatorNote) : nil)
            }
            .accessibilityIdentifier("\(identifier)-\(action.rawValue)-confirm")
        }
    }

    private var isConfirming: Binding<Bool> {
        Binding(
            get: { confirming.map(actions.contains) ?? false },
            set: { presented in
                guard !presented else { return }
                confirming = nil
                operatorNote = ""
            }
        )
    }

    private func takesNote(_ action: AccountLifecycleAction) -> Bool {
        collectsOperatorNote && action == .suspend
    }
}
