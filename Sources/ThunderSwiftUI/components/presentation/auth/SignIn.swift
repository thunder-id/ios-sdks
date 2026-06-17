import SwiftUI
import ThunderID

/// Full app-native sign-in form. Drives the Flow Execution API loop (spec §8.4 Presentation).
public struct SignIn: View {
    @EnvironmentObject private var state: ThunderState
    @EnvironmentObject private var i18n: ThunderI18n
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
                Text(i18n.resolve("signIn.title"))
                    .font(.title2)
                    .bold()
                    .accessibilityAddTraits(.isHeader)
                if let error = signInState.error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
                VStack(spacing: 12) {
                    ForEach(signInState.inputs.indices, id: \.self) { index in
                        let input = signInState.inputs[index]
                        if input.type == "PASSWORD_INPUT" {
                            SecureField(input.name, text: signInState.binding(for: input.name))
                                .accessibilityLabel(input.name)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 56)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 1))
                        } else {
                            TextField(input.name, text: signInState.binding(for: input.name))
                                .accessibilityLabel(input.name)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 56)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 1))
                        }
                    }
                }
                ForEach(signInState.actions, id: \.id) { action in
                    Button {
                        signInState.submit(actionId: action.id)
                    } label: {
                        Group {
                            if signInState.isLoading {
                                ProgressView().progressViewStyle(.circular).tint(.white)
                            } else {
                                Text(action.label ?? i18n.resolve("signIn.submit"))
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
                    .accessibilityLabel(action.label ?? i18n.resolve("signIn.submit"))
                }
            }
        }
    }
}

/// State container passed to the BaseSignIn builder.
@MainActor
public final class SignInState: ObservableObject {
    @Published public fileprivate(set) var inputs: [FlowInput] = []
    @Published public fileprivate(set) var actions: [FlowAction] = []
    @Published public fileprivate(set) var isLoading: Bool = false
    @Published public fileprivate(set) var error: String?

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
        actions = response.data?.actions ?? []
    }
}

/// Unstyled base variant (spec §8.3).
public struct BaseSignIn<Content: View>: View {
    @EnvironmentObject private var state: ThunderState
    public let applicationId: String
    public let onComplete: (() -> Void)?
    public let onError: ((String) -> Void)?
    public let content: (SignInState) -> Content

    @StateObject private var signInState = SignInState { _, _, _, _ in }

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
    }

    private func initFlow() async {
        signInState.isLoading = true
        defer { signInState.isLoading = false }
        do {
            let request = EmbeddedFlowRequestConfig(applicationId: applicationId, flowType: .authentication)
            let payload = EmbeddedSignInPayload(actionId: "__initiate__")
            let response = try await state.client.signIn(payload: payload, request: request)
            await handleResponse(response)
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
            await handleResponse(response)
        } catch {
            signInState.error = error.localizedDescription
            onError?(error.localizedDescription)
        }
    }

    private func handleResponse(_ response: EmbeddedFlowResponse) async {
        switch response.flowStatus {
        case .complete:
            await state.refresh()
            onComplete?()
        case .promptOnly:
            signInState.update(from: response)
        case .error:
            let msg = response.failureReason ?? "Sign-in failed"
            signInState.error = msg
            onError?(msg)
        }
    }
}
