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
}
