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

// MARK: - Color Helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let alpha, red, green, blue: UInt64
        switch hex.count {
        case 3:
            (alpha, red, green, blue) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (alpha, red, green, blue) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (alpha, red, green, blue) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (alpha, red, green, blue) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}

// MARK: - ThunderID Logo Mark

private struct TdMarkView: View {
    let height: CGFloat
    let dark: Bool

    private var width: CGFloat { height * (207.0 / 257.0) }

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / 207.0
            let scaleY = size.height / 257.0

            func scaledPath(_ pathData: Path) -> Path {
                pathData.applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
            }

            // Path 1: wordmark top-left bar — text color
            var path1 = Path()
            path1.move(to: CGPoint(x: 55.4763, y: 26.4391))
            path1.addLine(to: CGPoint(x: 58.8866, y: 0))
            path1.addLine(to: CGPoint(x: 0, y: 0))
            path1.addLine(to: CGPoint(x: 0, y: 26.4391))
            path1.closeSubpath()
            context.fill(scaledPath(path1), with: .color(dark ? Color(hex: "E8F4FF") : Color(hex: "05213F")))

            // Path 2: left bar — blue
            var path2 = Path()
            path2.move(to: CGPoint(x: 39.8438, y: 147.407))
            path2.addLine(to: CGPoint(x: 49.5455, y: 72.2839))
            path2.addLine(to: CGPoint(x: 0, y: 72.2839))
            path2.addLine(to: CGPoint(x: 0, y: 256.743))
            path2.addLine(to: CGPoint(x: 60.5602, y: 256.743))
            path2.addLine(to: CGPoint(x: 80.048, y: 147.407))
            path2.closeSubpath()
            context.fill(scaledPath(path2), with: .color(Color(hex: "3688FF")))

            // Path 3: right bolt — blue
            var path3 = Path()
            path3.move(to: CGPoint(x: 192.42, y: 59.361))
            path3.addCurve(
                to: CGPoint(x: 150.903, y: 15.3381),
                control1: CGPoint(x: 182.782, y: 40.2307),
                control2: CGPoint(x: 168.929, y: 25.5705)
            )
            path3.addCurve(
                to: CGPoint(x: 133.703, y: 7.5208),
                control1: CGPoint(x: 145.501, y: 12.2662),
                control2: CGPoint(x: 139.761, y: 9.6605)
            )
            path3.addLine(to: CGPoint(x: 115.401, y: 103.702))
            path3.addLine(to: CGPoint(x: 159.757, y: 103.702))
            path3.addLine(to: CGPoint(x: 76.2987, y: 256.743))
            path3.addLine(to: CGPoint(x: 83.3735, y: 256.743))
            path3.addCurve(
                to: CGPoint(x: 150.14, y: 241.236),
                control1: CGPoint(x: 109.449, y: 256.743),
                control2: CGPoint(x: 131.69, y: 251.574)
            )
            path3.addCurve(
                to: CGPoint(x: 192.356, y: 196.959),
                control1: CGPoint(x: 168.569, y: 230.897),
                control2: CGPoint(x: 182.634, y: 216.131)
            )
            path3.addCurve(
                to: CGPoint(x: 206.909, y: 128.043),
                control1: CGPoint(x: 202.058, y: 177.765),
                control2: CGPoint(x: 206.909, y: 154.8)
            )
            path3.addCurve(
                to: CGPoint(x: 192.441, y: 59.3821),
                control1: CGPoint(x: 206.909, y: 101.286),
                control2: CGPoint(x: 202.079, y: 78.5123)
            )
            path3.closeSubpath()
            context.fill(scaledPath(path3), with: .color(Color(hex: "3688FF")))
        }
        .frame(width: width, height: height)
    }
}

// MARK: - AuthView (Landing Screen)

struct AuthView: View {
    @EnvironmentObject private var state: ThunderIDState
    @Environment(\.colorScheme) private var colorScheme

    private var applicationId: String {
        (try? state.client.getConfiguration())?.applicationId ?? ""
    }

    @State private var showSignUp = false
    @State private var showSignIn = false
    @State private var showRecover = false

    private var isDark: Bool { colorScheme == .dark }

    private var bgColor: Color { isDark ? Color(hex: "080f1c") : Color(hex: "F7F9FC") }
    private var textColor: Color { isDark ? Color(hex: "E0EAFF") : Color(hex: "05213F") }
    private var mutedColor: Color { isDark ? Color(hex: "E0EAFF").opacity(0.48) : Color(hex: "5A7085") }
    private var borderColor: Color { isDark ? Color.white.opacity(0.09) : Color(hex: "DDE3EC") }
    private var cardColor: Color { isDark ? Color(hex: "111c2e") : Color(hex: "ffffff") }
    private var primaryBlue: Color { Color(hex: "3688FF") }

    private let featureTags = ["OAuth 2.0", "PKCE", "JWT", "MFA", "SSO"]

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo mark
                TdMarkView(height: 64, dark: isDark)
                    .padding(.bottom, 32)

                // Headline
                Text("Authentication\nfor developers.")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .multilineTextAlignment(.center)
                    .foregroundColor(textColor)
                    .padding(.horizontal, 32)

                // Subtext
                Text("OAuth 2.0, PKCE, MFA, and JWT\n— out of the box in minutes.")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundColor(mutedColor)
                    .padding(.top, 12)
                    .padding(.horizontal, 32)

                // Feature tags
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(featureTags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(primaryBlue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(primaryBlue.opacity(0.1))
                                .overlay(
                                    Capsule()
                                        .stroke(primaryBlue.opacity(0.3), lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.top, 24)

                Spacer()

                // CTAs
                VStack(spacing: 12) {
                    Button {
                        showSignUp = true
                    } label: {
                        Text("Get started")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(primaryBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        showSignIn = true
                    } label: {
                        Text("Sign in")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(primaryBlue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(cardColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(primaryBlue, lineWidth: 1.5)
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        // Sign In sheet
        .sheet(isPresented: $showSignIn) {
            SignInSheet(
                applicationId: applicationId,
                isDark: isDark,
                bgColor: bgColor,
                textColor: textColor,
                mutedColor: mutedColor,
                primaryBlue: primaryBlue
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // Sign Up sheet
        .sheet(isPresented: $showSignUp) {
            SignUpSheet(
                applicationId: applicationId,
                isDark: isDark,
                bgColor: bgColor,
                textColor: textColor,
                mutedColor: mutedColor,
                primaryBlue: primaryBlue
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // Recover sheet
        .sheet(isPresented: $showRecover) {
            RecoverSheet(
                isDark: isDark,
                bgColor: bgColor,
                textColor: textColor,
                mutedColor: mutedColor,
                primaryBlue: primaryBlue
            ) {
                showRecover = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showSignIn = true
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Sign In Sheet

private struct SignInSheet: View {
    let applicationId: String
    let isDark: Bool
    let bgColor: Color
    let textColor: Color
    let mutedColor: Color
    let primaryBlue: Color

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                SignIn(applicationId: applicationId)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Spacer()
            }
        }
    }
}

// MARK: - Sign Up Sheet

private struct SignUpSheet: View {
    let applicationId: String
    let isDark: Bool
    let bgColor: Color
    let textColor: Color
    let mutedColor: Color
    let primaryBlue: Color

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                SignUp(applicationId: applicationId)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Spacer()
            }
        }
    }
}

// MARK: - Recover Sheet

private struct RecoverSheet: View {
    let isDark: Bool
    let bgColor: Color
    let textColor: Color
    let mutedColor: Color
    let primaryBlue: Color
    let onBackToSignIn: () -> Void

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Button(action: onBackToSignIn) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Back to sign in")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(primaryBlue)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 32)
            }
        }
    }
}
