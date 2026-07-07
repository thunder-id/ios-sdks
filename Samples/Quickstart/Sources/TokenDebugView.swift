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

// MARK: - Token Parts

private struct TokenParts {
    let header: String
    let payload: String
    let signature: String
}

// MARK: - Token Screen

struct TokenScreen: View {
    @EnvironmentObject private var state: ThunderIDState
    let isDark: Bool
    let bgColor: Color
    let textColor: Color
    let mutedColor: Color
    let borderColor: Color
    let cardColor: Color
    let primaryBlue: Color
    let successGreen: Color
    let errorRed: Color
    let onBack: () -> Void

    @State private var accessToken: String = ""
    @State private var isLoadingToken = true
    @State private var tokenError: String?
    @State private var copiedToken = false

    private var tokenParts: TokenParts? {
        guard !accessToken.isEmpty else { return nil }
        let parts = accessToken.split(separator: ".").map(String.init)
        guard parts.count == 3 else { return nil }
        return TokenParts(header: parts[0], payload: parts[1], signature: parts[2])
    }

    private var decodedPayload: [String: Any] {
        decodeJwtPayload(accessToken)
    }

    private var prettyPayload: String {
        guard !decodedPayload.isEmpty else { return "{}" }
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        if let data = try? JSONSerialization.data(withJSONObject: decodedPayload, options: options),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private var expiryInfo: (label: String, isExpired: Bool)? {
        guard let exp = decodedPayload["exp"] as? Double else { return nil }
        let expDate = Date(timeIntervalSince1970: exp)
        let now = Date()
        if expDate < now { return ("Expired", true) }
        let minutes = Int(expDate.timeIntervalSince(now) / 60)
        return ("\(minutes) min", false)
    }

    private var issuer: String {
        (decodedPayload["iss"] as? String) ?? "—"
    }

    private var scopes: String {
        if let scopeValue = decodedPayload["scope"] as? String { return scopeValue }
        if let scopeList = decodedPayload["scp"] as? [String] { return scopeList.joined(separator: " ") }
        return "—"
    }

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

                Text("Token Debug")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(textColor)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                if isLoadingToken {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(primaryBlue)
                        Spacer()
                    }
                    .padding(.top, 48)
                } else if let error = tokenError {
                    Text("Error: \(error)")
                        .font(.system(size: 14))
                        .foregroundColor(errorRed)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                } else {
                    tokenCard
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    payloadCard
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    metaCard
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                }
            }
        }
        .background(bgColor)
        .task {
            await loadToken()
        }
    }

    private func loadToken() async {
        isLoadingToken = true
        tokenError = nil
        do {
            accessToken = try await state.client.getAccessToken()
        } catch {
            tokenError = error.localizedDescription
        }
        isLoadingToken = false
    }

    private var tokenCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Access token")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(textColor)
                Spacer()
                Button(action: copyToken) {
                    HStack(spacing: 4) {
                        Image(systemName: copiedToken ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                        Text(copiedToken ? "Copied" : "Copy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(copiedToken ? successGreen : primaryBlue)
                }
            }

            if let parts = tokenParts {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        Text(parts.header)
                            .foregroundColor(Color(hex: "ff7b72"))
                        Text(".")
                            .foregroundColor(Color.white.opacity(0.4))
                        Text(parts.payload)
                            .foregroundColor(Color(hex: "79c0ff"))
                        Text(".")
                            .foregroundColor(Color.white.opacity(0.4))
                        Text(parts.signature)
                            .foregroundColor(Color(hex: "3fb950"))
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(12)
                }
                .background(Color(hex: "0b1120"))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1))
    }

    private func copyToken() {
        #if canImport(UIKit)
        UIPasteboard.general.string = accessToken
        #endif
        copiedToken = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedToken = false
        }
    }

    private var payloadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("JWT Payload")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(textColor)
                Spacer()
                if let expiry = expiryInfo {
                    Text(expiry.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(expiry.isExpired ? errorRed : successGreen)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background((expiry.isExpired ? errorRed : successGreen).opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(prettyPayload)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isDark ? Color(hex: "E0EAFF") : Color(hex: "05213F"))
                    .padding(12)
                    .frame(minWidth: 0, alignment: .leading)
            }
            .background(isDark ? Color(hex: "0b1120") : Color(hex: "DDE3EC").opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1))
    }

    private var metaCard: some View {
        VStack(spacing: 0) {
            metaRow(label: "Issuer", value: issuer)
            Divider()
                .background(borderColor)
                .padding(.leading, 16)
            metaRow(label: "Scopes", value: scopes)
        }
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1))
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(mutedColor)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(textColor)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - JWT Decode Helper

private func decodeJwtPayload(_ token: String) -> [String: Any] {
    let parts = token.split(separator: ".").map(String.init)
    guard parts.count == 3 else { return [:] }
    var base64 = parts[1]
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 { base64 += "=" }
    guard let data = Data(base64Encoded: base64),
          let obj = try? JSONSerialization.jsonObject(with: data),
          let dict = obj as? [String: Any] else {
        return [:]
    }
    return dict
}
