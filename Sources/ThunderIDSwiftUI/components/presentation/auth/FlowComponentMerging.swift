/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

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
