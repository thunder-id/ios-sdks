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

/// App-native sign-up form. Drives the Flow Execution API registration loop (spec §8.4 Presentation).
public struct SignUp: View {
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
        BaseSignUp(applicationId: applicationId, onComplete: onComplete, onError: onError) { signUpState in
            VStack(alignment: .leading, spacing: 20) {
                if signUpState.components.isEmpty, signUpState.error == nil {
                    Text(i18n.resolve("signUp.title"))
                        .font(.title2)
                        .bold()
                        .accessibilityAddTraits(.isHeader)
                }
                if let error = signUpState.error {
                    // An error response carries no UI of its own — the previous step's
                    // inputs/actions are stale once the server has rejected the last
                    // submission, so show only the error instead of a form the user can
                    // no longer meaningfully interact with.
                    FlowErrorBanner(message: error)
                } else if signUpState.components.isEmpty {
                    VStack(spacing: 12) {
                        FlowInputFields(
                            inputs: signUpState.inputs,
                            bindValue: signUpState.binding(for:)
                        )
                    }
                    ForEach(signUpState.actions, id: \.id) { action in
                        actionButton(for: action, signUpState: signUpState)
                    }
                } else {
                    ForEach(Array(signUpState.components.enumerated()), id: \.offset) { _, component in
                        componentView(for: component, signUpState: signUpState)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func actionButton(for action: FlowAction, signUpState: SignUpState) -> some View {
        // Only the button matching the in-flight submission shows a spinner; the rest stay
        // disabled (to prevent overlapping submits) but keep their label instead of every
        // button spinning together.
        let isActiveAction = signUpState.loadingActionId == nil || signUpState.loadingActionId == action.id
        let isSpinning = signUpState.isLoading && isActiveAction
        let isBlocked = signUpState.isLoading && !isActiveAction

        if action.eventType?.uppercased() == "TRIGGER" {
            triggerButton(for: action, signUpState: signUpState, isSpinning: isSpinning, isBlocked: isBlocked)
        } else {
            Button {
                signUpState.submit(actionId: action.id)
            } label: {
                Group {
                    if isSpinning {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    } else {
                        Text(resolvedActionLabel(action, signUpState: signUpState))
                            .font(.body.weight(.medium))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .foregroundColor(.white)
            .background(Color.accentColor)
            .cornerRadius(8)
            .disabled(signUpState.isLoading)
            .accessibilityLabel(resolvedActionLabel(action, signUpState: signUpState))
            .accessibilityIdentifier("thunderid-action-\(action.id)")
        }
    }

    @ViewBuilder
    func triggerButton(
        for action: FlowAction,
        signUpState: SignUpState,
        isSpinning: Bool,
        isBlocked: Bool
    ) -> some View {
        let iconIdentity = action.icon?.lowercased() ?? ""
        let identity = iconIdentity + (action.ref ?? "").lowercased() + (action.label ?? "").lowercased()
        if identity.contains("google") {
            GoogleButton(
                label: i18n.resolve("signIn.continueWithGoogle"),
                isLoading: isSpinning,
                disabled: isBlocked
            ) {
                signUpState.submit(actionId: action.id)
            }
        } else if identity.contains("github") {
            GitHubButton(
                label: i18n.resolve("signIn.continueWithGithub"),
                isLoading: isSpinning,
                disabled: isBlocked
            ) {
                signUpState.submit(actionId: action.id)
            }
        } else if identity.contains("passkey") {
            PasskeyButton(
                label: resolvedActionLabel(action, signUpState: signUpState),
                isLoading: isSpinning,
                disabled: isBlocked
            ) {
                signUpState.submit(actionId: action.id)
            }
        } else {
            GenericTriggerButton(
                label: resolvedActionLabel(action, signUpState: signUpState),
                isLoading: isSpinning,
                disabled: isBlocked
            ) {
                signUpState.submit(actionId: action.id)
            }
        }
    }

    private func resolvedActionLabel(_ action: FlowAction, signUpState: SignUpState) -> String {
        guard let label = action.label else {
            return i18n.resolve("signUp.submit")
        }
        return signUpState.templateResolver?.resolve(label) ?? label
    }
}

/// Mutable state passed to the BaseSignUp builder.
@MainActor
public final class SignUpState: ObservableObject {
    @Published public fileprivate(set) var inputs: [FlowInput] = []
    @Published public fileprivate(set) var actions: [FlowAction] = []
    @Published public fileprivate(set) var components: [FlowComponent] = []
    @Published public fileprivate(set) var isLoading: Bool = false
    /// The actionId currently being submitted, if known. When set, only the button matching
    /// this id shows a spinner while `isLoading` is true — the rest are disabled but keep
    /// their label instead of every button spinning together.
    @Published public fileprivate(set) var loadingActionId: String?
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
        Binding(get: { self.fieldValues[name] ?? "" }, set: { self.fieldValues[name] = $0 })
    }

    public func submit(actionId: String) {
        loadingActionId = actionId
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
public struct BaseSignUp<Content: View>: View {
    @EnvironmentObject private var state: ThunderIDState
    public let applicationId: String
    public let onComplete: (() -> Void)?
    public let onError: ((String) -> Void)?
    public let content: (SignUpState) -> Content

    @StateObject private var signUpState = SignUpState { _, _, _, _ in }

    public init(
        applicationId: String,
        onComplete: (() -> Void)? = nil,
        onError: ((String) -> Void)? = nil,
        @ViewBuilder content: @escaping (SignUpState) -> Content
    ) {
        self.applicationId = applicationId
        self.onComplete = onComplete
        self.onError = onError
        self.content = content
    }

    public var body: some View {
        content(signUpState)
            .task {
                signUpState.submitAction = { actionId, inputs, flowId, challengeToken in
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
    /// labels/placeholders can be resolved for display. Failures are swallowed silently — metadata
    /// resolution must never surface as a sign-up error or block the flow from rendering.
    private func loadFlowMeta() async {
        guard let metaDict = try? await state.client.getFlowMeta(applicationId: applicationId) else {
            return
        }
        signUpState.setTemplateResolver(FlowTemplateResolver(meta: metaDict))
    }

    private func initFlow() async {
        signUpState.isLoading = true
        defer { signUpState.isLoading = false }
        do {
            let response = try await state.client.signUp()
            await handleResponse(response)
        } catch {
            signUpState.error = error.localizedDescription
            onError?(error.localizedDescription)
        }
    }

    private func submit(actionId: String, inputs: [String: String], flowId: String?, challengeToken: String?) async {
        signUpState.isLoading = true
        defer {
            signUpState.isLoading = false
            signUpState.loadingActionId = nil
        }
        do {
            let payload = EmbeddedSignInPayload(
                flowId: flowId, actionId: actionId, inputs: inputs, challengeToken: challengeToken
            )
            let response = try await state.client.signUp(payload: payload)
            await handleResponse(response)
        } catch {
            signUpState.error = error.localizedDescription
            onError?(error.localizedDescription)
        }
    }

    private func handleResponse(_ response: EmbeddedFlowResponse) async {
        switch response.flowStatus {
        case .complete:
            await state.refresh()
            onComplete?()
        case .promptOnly:
            signUpState.update(from: response)
        case .error:
            let msg = response.failureReason ?? "Sign-up failed"
            signUpState.error = msg
            onError?(msg)
        }
    }
}
