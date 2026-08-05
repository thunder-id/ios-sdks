// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

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
                        primaryBlue: primaryBlue
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

// MARK: - Claim Decoding Helper

/// Reads a unix-seconds numeric claim (`Int` or `Double`) from a decoded JWT/userinfo claims map.
func claimUnixSeconds(_ codable: AnyCodable?) -> TimeInterval? {
    guard let value = codable?.value else { return nil }
    if let intValue = value as? Int { return TimeInterval(intValue) }
    if let doubleValue = value as? Double { return doubleValue }
    return nil
}

// MARK: - Next Step Model

private struct NextStep {
    let number: String
    let title: String
    let subtitle: String
    let href: String
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

    private var greetingName: String {
        if let given = state.user?.claims?["given_name"]?.value as? String, !given.isEmpty {
            return given
        }
        if let email = state.user?.email, let prefix = email.split(separator: "@").first, !prefix.isEmpty {
            return String(prefix)
        }
        return "there"
    }

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
        NextStep(
            number: "01",
            title: "Explore use cases",
            subtitle: "See what you can build — auth flows for web, mobile, APIs, and agents.",
            href: "https://thunderid.dev/docs/next/use-cases/overview/"
        ),
        NextStep(
            number: "02",
            title: "Learn about flows",
            subtitle: "Understand how authorization code, PKCE, client credentials, and device flows work.",
            href: "https://thunderid.dev/docs/next/guides/flows/what-are-flows/"
        ),
        NextStep(
            number: "03",
            title: "Style your experience",
            subtitle: "Customize the login UI, branding, and email templates to match your product.",
            href: "https://thunderid.dev/docs/next/guides/design/overview/"
        ),
        NextStep(
            number: "04",
            title: "Explore SDK APIs",
            subtitle: "Full iOS SDK reference — views, state objects, and configuration options.",
            href: "https://thunderid.dev/docs/next/sdks/ios/overview/"
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero: avatar + (date/session row, greeting row)
                heroSection
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

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

    private var heroSection: some View {
        HStack(alignment: .center, spacing: 14) {
            UserAvatar(size: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(currentDateString)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundColor(mutedColor)
                    Circle()
                        .fill(mutedColor.opacity(0.4))
                        .frame(width: 3, height: 3)
                    Circle()
                        .fill(successGreen)
                        .frame(width: 6, height: 6)
                    Text("Session active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(successGreen)
                }
                Text(greeting)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(textColor)
            }
        }
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

    @Environment(\.openURL) private var openURL

    private var stepsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(nextSteps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Divider()
                        .background(borderColor)
                        .padding(.leading, 16)
                }
                Button {
                    guard let url = URL(string: step.href) else { return }
                    openURL(url)
                } label: {
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
                .buttonStyle(.plain)
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

            // Sign out
            signOutRow
        }
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1))
    }

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
