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

// MARK: - App Screen Enum

private enum AppScreen {
    case home, profile, token
}

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject private var state: ThunderIDState
    @Environment(\.colorScheme) private var colorScheme

    @State private var screen: AppScreen = .home

    private var isDark: Bool { colorScheme == .dark }
    private var bgColor: Color { isDark ? Color(hex: "080f1c") : Color(hex: "F7F9FC") }
    private var textColor: Color { isDark ? Color(hex: "E0EAFF") : Color(hex: "05213F") }
    private var mutedColor: Color { isDark ? Color(hex: "E0EAFF").opacity(0.48) : Color(hex: "5A7085") }
    private var borderColor: Color { isDark ? Color.white.opacity(0.09) : Color(hex: "DDE3EC") }
    private var cardColor: Color { isDark ? Color(hex: "111c2e") : Color(hex: "ffffff") }
    private var primaryBlue: Color { Color(hex: "3688FF") }
    private var successGreen: Color { Color(hex: "2fbd6b") }
    private var errorRed: Color { Color(hex: "d95757") }

    var body: some View {
        NavigationStack {
            ZStack {
                bgColor.ignoresSafeArea()
                switch screen {
                case .home:
                    HomeScreen(
                        isDark: isDark,
                        bgColor: bgColor,
                        textColor: textColor,
                        mutedColor: mutedColor,
                        borderColor: borderColor,
                        cardColor: cardColor,
                        primaryBlue: primaryBlue,
                        successGreen: successGreen,
                        onProfile: { screen = .profile },
                        onToken: { screen = .token }
                    )
                case .profile:
                    ProfileScreen(
                        isDark: isDark,
                        bgColor: bgColor,
                        textColor: textColor,
                        mutedColor: mutedColor,
                        borderColor: borderColor,
                        cardColor: cardColor,
                        primaryBlue: primaryBlue,
                        successGreen: successGreen
                    ) {
                        screen = .home
                    }
                case .token:
                    TokenScreen(
                        isDark: isDark,
                        bgColor: bgColor,
                        textColor: textColor,
                        mutedColor: mutedColor,
                        borderColor: borderColor,
                        cardColor: cardColor,
                        primaryBlue: primaryBlue,
                        successGreen: successGreen,
                        errorRed: errorRed
                    ) {
                        screen = .home
                    }
                }
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }
}

// MARK: - Initials Helper

func userInitials(_ displayName: String?) -> String {
    guard let name = displayName, !name.isEmpty else { return "?" }
    let parts = name.split(separator: " ").map(String.init)
    if parts.count >= 2 {
        let first = parts[0].first.map(String.init) ?? ""
        let last = parts[1].first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
    return String(name.prefix(2)).uppercased()
}

// MARK: - Claim Decoding Helper

/// Reads a unix-seconds numeric claim (`Int` or `Double`) from a decoded JWT/userinfo claims map.
func claimUnixSeconds(_ codable: AnyCodable?) -> TimeInterval? {
    guard let value = codable?.value else { return nil }
    if let intValue = value as? Int { return TimeInterval(intValue) }
    if let doubleValue = value as? Double { return doubleValue }
    return nil
}

// MARK: - Avatar View

struct InitialsAvatar: View {
    let name: String?
    let size: CGFloat
    let primaryBlue: Color

    var body: some View {
        Circle()
            .fill(primaryBlue)
            .frame(width: size, height: size)
            .overlay(
                Text(userInitials(name))
                    .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            )
    }
}

// MARK: - Next Step Model

private struct NextStep {
    let number: String
    let title: String
    let subtitle: String
}

// MARK: - Home Screen

private struct HomeScreen: View {
    @EnvironmentObject private var state: ThunderIDState
    let isDark: Bool
    let bgColor: Color
    let textColor: Color
    let mutedColor: Color
    let borderColor: Color
    let cardColor: Color
    let primaryBlue: Color
    let successGreen: Color
    let onProfile: () -> Void
    let onToken: () -> Void

    private var displayName: String { state.user?.displayName ?? state.user?.username ?? "Guest" }
    private var greetingName: String { state.user?.displayName ?? state.user?.username ?? "there" }
    private var email: String? { state.user?.email }

    private var authTimeClaim: TimeInterval? { claimUnixSeconds(state.user?.claims?["auth_time"]) }
    private var expClaim: TimeInterval? { claimUnixSeconds(state.user?.claims?["exp"]) }

    private var organisationName: String {
        guard let handle = (try? state.client.getConfiguration())?.organizationHandle, !handle.isEmpty else {
            return "Default"
        }
        return handle
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String
        if hour < 12 {
            timeOfDay = "morning"
        } else if hour < 17 {
            timeOfDay = "afternoon"
        } else {
            timeOfDay = "evening"
        }
        return "Good \(timeOfDay), \(greetingName)."
    }

    private var currentDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date()).uppercased()
    }

    private let nextSteps: [NextStep] = [
        NextStep(number: "01", title: "Secure your API", subtitle: "Add token validation to your backend."),
        NextStep(number: "02", title: "Add social login", subtitle: "GitHub, Google, and OIDC providers."),
        NextStep(number: "03", title: "Enable MFA", subtitle: "TOTP and passkey support."),
        NextStep(number: "04", title: "Explore the SDK", subtitle: "API reference and guides.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Identity header card
                identityCard
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                // Date + greeting
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentDateString)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundColor(mutedColor)
                    Text(greeting)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(textColor)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)

                // Stats row
                statsRow
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                // What's next section
                sectionHeader("WHAT'S NEXT")
                    .padding(.horizontal, 24)
                    .padding(.top, 28)

                stepsCard
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                // User actions
                sectionHeader("ACCOUNT")
                    .padding(.horizontal, 24)
                    .padding(.top, 28)

                actionsCard
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
            }
        }
        .background(bgColor)
    }

    private var identityCard: some View {
        HStack(spacing: 14) {
            InitialsAvatar(name: displayName, size: 48, primaryBlue: primaryBlue)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textColor)
                if let email {
                    Text(email)
                        .font(.system(size: 13))
                        .foregroundColor(mutedColor)
                }
            }

            Spacer()

            // Session active badge
            HStack(spacing: 5) {
                Circle()
                    .fill(successGreen)
                    .frame(width: 7, height: 7)
                Text("Session active")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(successGreen)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(successGreen.opacity(0.12))
            .clipShape(Capsule())
        }
        .padding(16)
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1))
    }

    private var statsRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 0) {
                statItem(value: signedInAtText, label: "Signed in at")
                Divider()
                    .frame(width: 1, height: 36)
                    .background(borderColor)
                statItem(value: sessionExpiresInText(now: context.date), label: "Session expires in")
                Divider()
                    .frame(width: 1, height: 36)
                    .background(borderColor)
                statItem(value: organisationName, label: "Organisation")
            }
            .padding(.vertical, 16)
        }
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1))
    }

    private var signedInAtText: String {
        guard let authTime = authTimeClaim else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: authTime))
    }

    private func sessionExpiresInText(now: Date) -> String {
        guard let exp = expClaim else { return "—" }
        let secondsLeft = Int(exp - now.timeIntervalSince1970)
        if secondsLeft <= 0 { return "Expired" }
        if secondsLeft < 3600 {
            return "\(secondsLeft / 60)m \(secondsLeft % 60)s"
        }
        return "\(secondsLeft / 3600)h \((secondsLeft % 3600) / 60)m"
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(textColor)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(mutedColor)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.2)
            .foregroundColor(mutedColor)
    }

    private var stepsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(nextSteps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Divider()
                        .background(borderColor)
                        .padding(.leading, 16)
                }
                HStack(spacing: 14) {
                    Text(step.number)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(primaryBlue)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(textColor)
                        Text(step.subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(mutedColor)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(mutedColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1))
    }

    private var actionsCard: some View {
        VStack(spacing: 0) {
            // My profile
            Button(action: onProfile) {
                actionRow(icon: "person.circle", label: "My profile", color: textColor)
            }

            Divider()
                .background(borderColor)
                .padding(.leading, 52)

            // Token debug
            Button(action: onToken) {
                actionRow(icon: "key.horizontal", label: "Token debug", color: textColor)
            }

            Divider()
                .background(borderColor)
                .padding(.leading, 52)

            // Settings (no-op)
            Button(action: noop) {
                actionRow(icon: "gearshape", label: "Settings", color: textColor)
            }

            Divider()
                .background(borderColor)
                .padding(.leading, 52)

            // Sign out
            signOutRow
        }
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1))
    }

    private func noop() {}

    private func actionRow(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(color)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(mutedColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var signOutRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 18))
                .foregroundColor(Color(hex: "d95757"))
                .frame(width: 24)
            SignOutButton()
                .tint(Color(hex: "d95757"))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// Color(hex:) is defined in SignInView.swift and shared across the module.
