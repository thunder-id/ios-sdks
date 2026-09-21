// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

// MARK: - Profile Screen

struct ProfileScreen: View {
    let isDark: Bool
    let bgColor: Color
    let textColor: Color
    let mutedColor: Color
    let borderColor: Color
    let cardColor: Color
    let primaryBlue: Color
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Back nav
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Home")
                            .font(.system(size: 16))
                    }
                    .foregroundColor(primaryBlue)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)

                // UserProfile owns the /users/me data, edit/save state, and its own styling
                // (light/dark-adaptive), so this screen only supplies the surrounding chrome.
                UserProfile()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                // ChangeCredential manages the credential declared on the user type schema; its
                // heading and labels follow that credential's own display name from the console.
                ChangeCredential()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .background(bgColor)
    }
}
