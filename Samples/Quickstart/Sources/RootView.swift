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
import ThunderIDSwiftUI

struct RootView: View {
    @EnvironmentObject private var state: ThunderIDState

    var body: some View {
        if !state.isInitialized || state.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading\u{2026}")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = state.error {
            VStack(spacing: 16) {
                Text("Configuration error: \(error)\n\nCheck your .env values.")
                    .multilineTextAlignment(.center)
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.isSignedIn {
            HomeView()
        } else {
            AuthView()
        }
    }
}
