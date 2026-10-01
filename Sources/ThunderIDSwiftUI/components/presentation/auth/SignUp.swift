// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

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
        } else if FlowComponentMerging.isOutlinedVariant(action.variant) {
            GenericTriggerButton(
                label: resolvedActionLabel(action, signUpState: signUpState),
                isLoading: isSpinning,
                disabled: isBlocked
            ) {
                signUpState.submit(actionId: action.id)
            }
            .accessibilityIdentifier("thunderid-action-\(action.id)")
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
    /// The step's `additionalData`, read by data-bound display components through their `source`.
    @Published public fileprivate(set) var additionalData: [String: AnyCodable] = [:]
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
        additionalData = response.data?.additionalData ?? [:]
        actions = FlowComponentMerging.enrichActions(response.data?.actions ?? [], with: components)
        seedFieldValues()
    }

    func setTemplateResolver(_ resolver: FlowTemplateResolver) {
        templateResolver = resolver
    }

    /// Two failure modes come from the same source — `fieldValues` only ever grows via the
    /// binding's setter, never shrinks or gets pre-populated:
    ///
    /// 1. A field a user never focuses (or whose binding update races with a fast submit right
    ///    after typing, as can happen under a loaded CI runner) never gets an entry, since the
    ///    binding only writes on change. Submitting with that key missing — as opposed to
    ///    present but empty — makes the server re-prompt for just that field with no action to
    ///    submit it through, permanently stalling the flow.
    /// 2. A field from a *previous* step lingers in `fieldValues` (it's never cleared on
    ///    advancing), so the next step's submission carries it along unasked. The server
    ///    interprets that leaked field as an attempt to re-satisfy the earlier step and bounces
    ///    the flow back to it instead of processing the current one.
    ///
    /// Recomputing `fieldValues` from scratch on every step — keeping only values for names the
    /// current step actually declares (from either the flat `inputs` list or the component tree;
    /// some steps only populate one of the two), defaulting anything newly required to an empty
    /// string — keeps a submission limited to exactly what this step asks for, never more or
    /// less.
    private func seedFieldValues() {
        let currentNames = Set(inputs.map(\.name)).union(FlowComponentMerging.inputNames(in: components))
        fieldValues = fieldValues.filter { currentNames.contains($0.key) }
        for name in currentNames where fieldValues[name] == nil {
            fieldValues[name] = ""
        }
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
