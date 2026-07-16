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
import ThunderID

/// Full app-native sign-in form. Drives the Flow Execution API loop (spec §8.4 Presentation).
public struct SignIn: View {
    @EnvironmentObject private var state: ThunderIDState
    @EnvironmentObject var i18n: ThunderIDI18n
    public let applicationId: String
    public let onComplete: (() -> Void)?
    public let onError: ((String) -> Void)?

    public init(
        applicationId: String,
        onComplete: (() -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        self.applicationId = applicationId
        self.onComplete = onComplete
        self.onError = onError
    }

    public var body: some View {
        BaseSignIn(applicationId: applicationId, onComplete: onComplete, onError: onError) { signInState in
            VStack(alignment: .leading, spacing: 20) {
                if signInState.components.isEmpty {
                    Text(i18n.resolve("signIn.title"))
                        .font(.title2)
                        .bold()
                        .accessibilityAddTraits(.isHeader)
                }
                if let error = signInState.error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
                if signInState.components.isEmpty {
                    VStack(spacing: 12) {
                        FlowInputFields(
                            inputs: signInState.inputs,
                            bindValue: signInState.binding(for:)
                        )
                    }
                    ForEach(signInState.actions, id: \.id) { action in
                        actionButton(for: action, signInState: signInState)
                    }
                } else {
                    ForEach(Array(signInState.components.enumerated()), id: \.offset) { _, component in
                        componentView(for: component, signInState: signInState)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func actionButton(for action: FlowAction, signInState: SignInState) -> some View {
        if action.eventType?.uppercased() == "TRIGGER" {
            triggerButton(for: action, signInState: signInState)
        } else {
            Button {
                signInState.submit(actionId: action.id)
            } label: {
                Group {
                    if signInState.isLoading {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    } else {
                        Text(resolvedActionLabel(action, signInState: signInState))
                            .font(.body.weight(.medium))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .foregroundColor(.white)
            .background(Color.accentColor)
            .cornerRadius(8)
            .disabled(signInState.isLoading)
            .accessibilityLabel(resolvedActionLabel(action, signInState: signInState))
                    .accessibilityIdentifier("thunderid-action-\(action.id)")
        }
    }

    @ViewBuilder
    func triggerButton(for action: FlowAction, signInState: SignInState) -> some View {
        let iconIdentity = action.icon?.lowercased() ?? ""
        let identity = iconIdentity + (action.ref ?? "").lowercased() + (action.label ?? "").lowercased()
        if identity.contains("google") {
            GoogleButton(
                label: i18n.resolve("signIn.continueWithGoogle"),
                isLoading: signInState.isLoading
            ) {
                signInState.submit(actionId: action.id)
            }
        } else if identity.contains("github") {
            GitHubButton(
                label: i18n.resolve("signIn.continueWithGithub"),
                isLoading: signInState.isLoading
            ) {
                signInState.submit(actionId: action.id)
            }
        } else {
            GenericTriggerButton(
                label: resolvedActionLabel(action, signInState: signInState),
                isLoading: signInState.isLoading
            ) {
                signInState.submit(actionId: action.id)
            }
        }
    }

    private func resolvedActionLabel(_ action: FlowAction, signInState: SignInState) -> String {
        guard let label = action.label else {
            return i18n.resolve("signIn.submit")
        }
        return signInState.templateResolver?.resolve(label) ?? label
    }
}

/// State container passed to the BaseSignIn builder.
@MainActor
public final class SignInState: ObservableObject {
    @Published public fileprivate(set) var inputs: [FlowInput] = []
    @Published public fileprivate(set) var actions: [FlowAction] = []
    @Published public fileprivate(set) var components: [FlowComponent] = []
    @Published public fileprivate(set) var isLoading: Bool = false
    @Published public fileprivate(set) var error: String?
    @Published public fileprivate(set) var templateResolver: FlowTemplateResolver?

    private var fieldValues: [String: String] = [:]
    private var flowId: String?
    private var challengeToken: String?
    var submitAction: (String, [String: String], String?, String?) -> Void

    init(submit: @escaping (String, [String: String], String?, String?) -> Void) {
        self.submitAction = submit
    }

    public func binding(for name: String) -> Binding<String> {
        Binding(
            get: { self.fieldValues[name] ?? "" },
            set: { self.fieldValues[name] = $0 }
        )
    }

    public func submit(actionId: String) {
        submitAction(actionId, fieldValues, flowId, challengeToken)
    }

    func update(from response: EmbeddedFlowResponse) {
        flowId = response.flowId
        challengeToken = response.challengeToken
        inputs = response.data?.inputs ?? []
        components = response.data?.meta?.components ?? []
        actions = FlowComponentMerging.enrichActions(response.data?.actions ?? [], with: components)
    }

    func setTemplateResolver(_ resolver: FlowTemplateResolver) {
        templateResolver = resolver
    }
}

/// Unstyled base variant (spec §8.3).
public struct BaseSignIn<Content: View>: View {
    @EnvironmentObject private var state: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    public let applicationId: String
    public let onComplete: (() -> Void)?
    public let onError: ((String) -> Void)?
    public let content: (SignInState) -> Content

    @StateObject private var signInState = SignInState { _, _, _, _ in }
    @State private var federatedAuthSession = FederatedAuthSession()

    public init(
        applicationId: String,
        onComplete: (() -> Void)? = nil,
        onError: ((String) -> Void)? = nil,
        @ViewBuilder content: @escaping (SignInState) -> Content
    ) {
        self.applicationId = applicationId
        self.onComplete = onComplete
        self.onError = onError
        self.content = content
    }

    public var body: some View {
        content(signInState)
            .task {
                signInState.submitAction = { actionId, inputs, flowId, challengeToken in
                    Task {
                        await submit(
                            actionId: actionId, inputs: inputs, flowId: flowId, challengeToken: challengeToken
                        )
                    }
                }
                await initFlow()
            }
            .task {
                await loadFlowMeta()
            }
    }

    /// Fetches `GET /flow/meta` in parallel with `initFlow()` so template literals in component
    /// labels/placeholders (e.g. `{{ t(signin:forms.credentials.fields.username.label) }}`) can
    /// be resolved for display. Failures are swallowed silently — metadata resolution must never
    /// surface as a sign-in error or block the flow from rendering.
    private func loadFlowMeta() async {
        guard let metaDict = try? await state.client.getFlowMeta(applicationId: applicationId) else {
            return
        }
        signInState.setTemplateResolver(FlowTemplateResolver(meta: metaDict))
    }

    private func initFlow() async {
        signInState.isLoading = true
        defer { signInState.isLoading = false }
        do {
            let request = EmbeddedFlowRequestConfig(applicationId: applicationId, flowType: .authentication)
            let payload = EmbeddedSignInPayload(actionId: "__initiate__")
            let response = try await state.client.signIn(payload: payload, request: request)
            await handleResponse(response, actionId: "__initiate__")
        } catch {
            signInState.error = error.localizedDescription
            onError?(error.localizedDescription)
        }
    }

    private func submit(actionId: String, inputs: [String: String], flowId: String?, challengeToken: String?) async {
        signInState.isLoading = true
        defer { signInState.isLoading = false }
        do {
            let payload = EmbeddedSignInPayload(
                flowId: flowId, actionId: actionId, inputs: inputs, challengeToken: challengeToken
            )
            let request = EmbeddedFlowRequestConfig(applicationId: applicationId, flowType: .authentication)
            let response = try await state.client.signIn(payload: payload, request: request)
            await handleResponse(response, actionId: actionId)
        } catch {
            signInState.error = error.localizedDescription
            onError?(error.localizedDescription)
        }
    }

    private func handleResponse(_ response: EmbeddedFlowResponse, actionId: String) async {
        switch response.flowStatus {
        case .complete:
            await state.refresh()
            onComplete?()
        case .promptOnly:
            if response.type == "REDIRECTION", let redirectURL = response.data?.redirectURL {
                await handleRedirection(redirectURL, response: response, actionId: actionId)
            } else {
                signInState.update(from: response)
            }
        case .error:
            let msg = response.failureReason ?? "Sign-in failed"
            signInState.error = msg
            onError?(msg)
        }
    }

    private func handleRedirection(_ redirectURL: String, response: EmbeddedFlowResponse, actionId: String) async {
        guard let url = URL(string: redirectURL), let scheme = callbackURLScheme() else {
            let message = i18n.resolve("signIn.federatedError")
            signInState.error = message
            onError?(message)
            return
        }
        signInState.isLoading = true
        defer { signInState.isLoading = false }
        do {
            let callbackURL = try await federatedAuthSession.authenticate(url: url, callbackURLScheme: scheme)
            guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
                throw ThunderIDError(code: .invalidGrant, message: "Authorization code missing from callback URL")
            }
            await submit(
                actionId: actionId,
                inputs: ["code": code],
                flowId: response.flowId,
                challengeToken: response.challengeToken
            )
        } catch is FederatedAuthSession.CancelledError {
            // User dismissed the browser sheet — reset silently, no error surfaced.
        } catch {
            signInState.error = error.localizedDescription
            onError?(error.localizedDescription)
        }
    }

    private func callbackURLScheme() -> String? {
        guard let afterSignInUrl = try? state.client.getConfiguration().afterSignInUrl,
              let scheme = URLComponents(string: afterSignInUrl)?.scheme else {
            return nil
        }
        return scheme
    }
}
