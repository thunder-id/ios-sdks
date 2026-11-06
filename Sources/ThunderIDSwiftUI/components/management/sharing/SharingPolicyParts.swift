// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Describes a sharing policy's reach in translated words, as the server records it.
enum SharingScope {
    static func describe(_ policy: SharingPolicy, i18n: ThunderIDI18n) -> String {
        var parts: [String] = []
        if let all = policy.allUnits {
            parts.append(excluding(i18n.resolve("admin.sharing.scope.all_units"), all.excludedOuIds, i18n: i18n))
        }
        if let children = policy.childUnits {
            if children.mode == "selected" {
                let units = (children.units ?? []).map { unit in
                    unit.reach == "subtree"
                        ? i18n.resolve("admin.sharing.scope.subtree", ["unit": unit.ouId])
                        : unit.ouId
                }
                let list = units.joined(separator: ", ")
                parts.append(i18n.resolve("admin.sharing.scope.selected_children", ["units": list]))
            } else {
                let text = i18n.resolve("admin.sharing.scope.all_children")
                parts.append(excluding(text, children.excludedOuIds, i18n: i18n))
            }
        }
        if let roots = policy.otherTreeRoots {
            if roots.mode == "selected" {
                let units = (roots.units ?? []).map(\.ouId).joined(separator: ", ")
                parts.append(i18n.resolve("admin.sharing.scope.selected_other_roots", ["units": units]))
            } else {
                let text = i18n.resolve("admin.sharing.scope.all_other_roots")
                parts.append(excluding(text, roots.excludedOuIds, i18n: i18n))
            }
        }
        return parts.isEmpty ? i18n.resolve("admin.sharing.scope.none") : parts.joined(separator: " · ")
    }

    private static func excluding(_ scope: String, _ ids: [String]?, i18n: ThunderIDI18n) -> String {
        guard let ids, !ids.isEmpty else { return scope }
        return i18n.resolve("admin.sharing.scope.excluding", ["scope": scope, "units": ids.joined(separator: ", ")])
    }
}

/// What the sharing policy form submits: the reach beneath the issuer, or across every unit when an
/// existing policy already says so.
struct SharingPolicyDraft {
    enum Mode: String {
        case everywhere
        case allChildren
        case selected
    }

    var mode: Mode
    var units: String
    var subtree: Bool
    var excluded: String

    init(policy: SharingPolicy?) {
        let children = policy?.childUnits
        if policy?.allUnits != nil {
            mode = .everywhere
        } else {
            mode = children?.mode == "selected" ? .selected : .allChildren
        }
        units = (children?.units ?? []).map(\.ouId).joined(separator: ", ")
        subtree = children?.units?.contains { $0.reach == "subtree" } ?? false
        excluded = (policy?.allUnits?.excludedOuIds ?? children?.excludedOuIds ?? []).joined(separator: ", ")
    }

    var isValid: Bool { mode != .selected || !Self.ids(units).isEmpty }

    var childUnits: SharingChildUnits? {
        switch mode {
        case .everywhere: return nil
        case .allChildren: return .all(excluding: Self.optionalIds(excluded))
        case .selected:
            return .selected(Self.ids(units).map { SharingChildUnit(ouId: $0, reach: subtree ? "subtree" : "unit") })
        }
    }

    var allUnits: SharingAllUnits? {
        mode == .everywhere ? SharingAllUnits(excludedOuIds: Self.optionalIds(excluded)) : nil
    }

    static func ids(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func optionalIds(_ text: String) -> [String]? {
        let list = ids(text)
        return list.isEmpty ? nil : list
    }
}

/// The create and edit form of the built-in sharing policies UI.
struct SharingPolicyForm: View {
    let i18n: ThunderIDI18n
    let policy: SharingPolicy?
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onSubmit: (SharingPolicyDraft) -> Void
    @State private var draft: SharingPolicyDraft

    init(
        i18n: ThunderIDI18n,
        policy: SharingPolicy?,
        isSubmitting: Bool,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping (SharingPolicyDraft) -> Void
    ) {
        self.i18n = i18n
        self.policy = policy
        self.isSubmitting = isSubmitting
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        _draft = State(initialValue: SharingPolicyDraft(policy: policy))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdminPicker(
                label: i18n.resolve("admin.sharing.fields.mode"),
                name: "sharing-mode",
                options: modes,
                selection: Binding(
                    get: { draft.mode.rawValue },
                    set: { draft.mode = SharingPolicyDraft.Mode(rawValue: $0) ?? .allChildren }
                )
            )
            if draft.mode == .selected {
                AdminTextField(
                    label: i18n.resolve("admin.sharing.fields.units"),
                    name: "sharing-units",
                    isRequired: true,
                    text: $draft.units
                )
                Toggle(i18n.resolve("admin.sharing.fields.subtree"), isOn: $draft.subtree)
                    .accessibilityIdentifier("admin-field-sharing-subtree")
            } else {
                AdminTextField(
                    label: i18n.resolve("admin.sharing.fields.excluded"),
                    name: "sharing-excluded",
                    text: $draft.excluded
                )
            }
            Text(i18n.resolve("admin.sharing.fields.ids_hint"))
                .font(.footnote)
                .foregroundColor(.secondary)
            AdminFormActions(
                i18n: i18n,
                submitLabel: i18n.resolve("admin.sharing.save"),
                isSubmitting: isSubmitting,
                canSubmit: draft.isValid,
                onCancel: onCancel
            ) { if draft.isValid { onSubmit(draft) } }
        }
    }

    /// Every unit is offered only for a policy that already reaches every unit: a new policy cannot.
    private var modes: [AdminOption] {
        let everywhere = policy?.allUnits != nil
            ? [AdminOption(label: i18n.resolve("admin.sharing.scope.all_units"), value: "everywhere")]
            : []
        return everywhere + [
            AdminOption(label: i18n.resolve("admin.sharing.scope.all_children"), value: "allChildren"),
            AdminOption(label: i18n.resolve("admin.sharing.fields.mode_selected"), value: "selected")
        ]
    }
}

/// The resolved overlay rules for one organization unit, read only.
struct SharingOverlayPanel: View {
    let i18n: ThunderIDI18n
    let overlay: ResolvedOverlay

    var body: some View {
        AdminPanel(title: i18n.resolve("admin.sharing.overlay.title", ["unit": overlay.ouId ?? ""])) {
            VStack(alignment: .leading, spacing: 8) {
                AdminDetailList(items: [
                    (i18n.resolve("admin.sharing.overlay.visibility"), i18n.resolve(visibilityKey)),
                    (i18n.resolve("admin.sharing.overlay.ownership"), i18n.resolve(ownershipKey))
                ])
                let rules = (overlay.rules ?? [:]).sorted { $0.key < $1.key }
                if rules.isEmpty {
                    Text(i18n.resolve("admin.sharing.overlay.no_rules"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    AdminDetailList(items: rules.map { attribute, rule in
                        (attribute, ruleText(rule))
                    })
                }
            }
        }
        .accessibilityIdentifier("admin-sharing-overlay")
    }

    private var visibilityKey: String {
        overlay.visible == false ? "admin.sharing.overlay.hidden" : "admin.sharing.overlay.visible"
    }

    private var ownershipKey: String {
        overlay.isOwned == true ? "admin.sharing.overlay.owned" : "admin.sharing.overlay.shared"
    }

    private func ruleText(_ rule: OverlayRule) -> String {
        let accessKey = rule.editable == true ? "admin.sharing.overlay.editable" : "admin.sharing.overlay.locked"
        let access = i18n.resolve(accessKey)
        let values = rule.allowedValues ?? rule.value ?? []
        return values.isEmpty ? access : "\(access) · \(values.joined(separator: ", "))"
    }
}
