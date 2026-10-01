// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import ThunderID

/// Shared merge logic used by both `SignInState` and `SignUpState` to enrich the flat
/// `data.actions` array with presentation metadata (label, eventType, variant, icon) carried
/// only in `data.meta.components`.
enum FlowComponentMerging {
    /// Fills in any `nil` presentation fields on the flat `actions` array (label, eventType,
    /// variant, icon) from the matching `ACTION`-typed node in the component tree, matched by
    /// `ref` (falling back to `id`). Explicit flat values always win.
    static func enrichActions(_ actions: [FlowAction], with components: [FlowComponent]) -> [FlowAction] {
        let actionComponents = flattenActionComponents(components)
        return actions.map { action in
            guard let match = actionComponents.first(where: {
                ($0.ref != nil && $0.ref == action.ref) || ($0.id != nil && $0.id == action.id)
            }) else {
                return action
            }
            return action.merging(component: match)
        }
    }

    private static func flattenActionComponents(_ components: [FlowComponent]) -> [FlowComponent] {
        var result: [FlowComponent] = []
        for component in components {
            if component.type == "ACTION" {
                result.append(component)
            }
            if let children = component.components {
                result.append(contentsOf: flattenActionComponents(children))
            }
        }
        return result
    }

    /// Names of every `*_INPUT`-typed node in the component tree, matched the same way
    /// `inputComponentView` binds them (`ref`, falling back to `id`). Used to seed a fresh
    /// `fieldValues` entry for each field the component tree renders, even when the flat
    /// `inputs` list doesn't separately list it.
    static func inputNames(in components: [FlowComponent]) -> [String] {
        var result: [String] = []
        for component in components {
            if let type = component.type, type.hasSuffix("_INPUT"), let name = component.ref ?? component.id {
                result.append(name)
            }
            if let children = component.components {
                result.append(contentsOf: inputNames(in: children))
            }
        }
        return result
    }

    /// Whether a non-TRIGGER action asks for the outlined, secondary look rather than the filled
    /// primary one. A missing variant keeps the filled look, so flows that never set one render as before.
    static func isOutlinedVariant(_ variant: String?) -> Bool {
        ["SECONDARY", "OUTLINED"].contains(variant?.uppercased() ?? "")
    }
}
