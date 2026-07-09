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

/// Tappable button that starts the redirect-based sign-in flow (spec §8.4 Actions).
public struct SignInButton: View {
    @EnvironmentObject private var state: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    public let accessibilityIdentifier: String?
    public let onTap: (() -> Void)?

    public init(accessibilityIdentifier: String? = nil, onTap: (() -> Void)? = nil) {
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onTap = onTap
    }

    public var body: some View {
        BaseSignInButton(
            label: i18n.resolve("signIn.button"),
            isLoading: state.isLoading,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            onTap?()
        }
    }
}

/// Unstyled base variant (spec §8.3).
public struct BaseSignInButton: View {
    public let label: String
    public let isLoading: Bool
    public let accessibilityIdentifier: String?
    public let action: () -> Void

    public init(
        label: String,
        isLoading: Bool = false,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isLoading = isLoading
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        Button(action: isLoading ? {} : action) {
            Text(label)
        }
        .disabled(isLoading)
        .accessibilityLabel(label)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
        .frame(minWidth: 44, minHeight: 44)
    }
}
