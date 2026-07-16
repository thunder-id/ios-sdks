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

import SwiftUI

/// Shared outlined-button chrome for `eventType: TRIGGER` (federated login) actions: an icon
/// slot, a label, and a rounded-rect stroke — matching the "Continue with X" buttons rendered
/// below a SignIn form's "Or" divider.
struct TriggerButtonStyle<Icon: View>: View {
    let label: String
    let isLoading: Bool
    let onTap: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: isLoading ? {} : onTap) {
            HStack(spacing: 10) {
                icon
                Text(label)
                    .font(.body.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .foregroundColor(.primary)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4), lineWidth: 1))
        .disabled(isLoading)
        .accessibilityLabel(label)
    }
}

/// Generic outlined trigger button for TRIGGER actions with no dedicated brand adapter,
/// using the label supplied by the flow schema.
struct GenericTriggerButton: View {
    let label: String
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        TriggerButtonStyle(label: label, isLoading: isLoading, onTap: onTap) {
            EmptyView()
        }
    }
}
