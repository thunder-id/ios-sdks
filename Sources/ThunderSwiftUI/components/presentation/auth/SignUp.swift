import SwiftUI
import ThunderID

/// App-native sign-up form. Drives the Flow Execution API registration loop (spec §8.4 Presentation).
public struct SignUp: View {
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
        BaseSignUp(applicationId: applicationId, onComplete: onComplete, onError: onError) { signUpState in
            VStack(alignment: .leading, spacing: 20) {
                Text(i18n.resolve("signUp.title"))
                    .font(.title2)
                    .bold()
                    .accessibilityAddTraits(.isHeader)
                if let error = signUpState.error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
                VStack(spacing: 12) {
                    ForEach(signUpState.inputs.indices, id: \.self) { index in
                        let input = signUpState.inputs[index]
                        if input.type == "PASSWORD_INPUT" {
                            SecureField(input.name, text: signUpState.binding(for: input.name))
                                .accessibilityLabel(input.name)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 56)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 1))
                        } else {
                            TextField(input.name, text: signUpState.binding(for: input.name))
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
                ForEach(signUpState.actions, id: \.id) { action in
                    Button {
                        signUpState.submit(actionId: action.id)
                    } label: {
                        Group {
                            if signUpState.isLoading {
                                ProgressView().progressViewStyle(.circular).tint(.white)
                            } else {
                                Text(action.label ?? i18n.resolve("signUp.submit"))
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
                }
            }
        }
    }
}

/// Mutable state passed to the BaseSignUp builder.
@MainActor
public final class SignUpState: ObservableObject {
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
        Binding(get: { self.fieldValues[name] ?? "" }, set: { self.fieldValues[name] = $0 })
    }

    public func submit(actionId: String) { submitAction(actionId, fieldValues, flowId, challengeToken) }

    func update(from response: EmbeddedFlowResponse) {
        flowId = response.flowId
        challengeToken = response.challengeToken
        inputs = response.data?.inputs ?? []
        actions = response.data?.actions ?? []
    }
}

/// Unstyled base variant (spec §8.3).
public struct BaseSignUp<Content: View>: View {
    @EnvironmentObject private var state: ThunderState
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
        defer { signUpState.isLoading = false }
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
