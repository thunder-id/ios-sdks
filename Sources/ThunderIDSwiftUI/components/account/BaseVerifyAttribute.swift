// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Where a verification stands.
public enum VerifyAttributePhase: Equatable {
    /// Waiting for the user schema or the server's first step.
    case loading
    /// Showing a step: a code to enter, or a link the user opens outside the app.
    case active
    /// The server recorded the verification.
    case complete
    /// The server refused the verification, the request failed, or the attribute cannot be verified.
    case failed
}

/// The requests a verification makes, so the state can be driven without a view.
struct VerifyAttributeEngine {
    var loadSchema: () async throws -> [String: AttributeSchema]
    var start: () async throws -> EmbeddedFlowResponse
    var submit: (EmbeddedSignInPayload) async throws -> EmbeddedFlowResponse
    var readProfile: () async throws -> ThunderID.UserProfile

    /// The requests the component makes: through the SDK client, with `/users/me` read again into the
    /// shared state, so a standalone component shows a recorded verification without a host.
    @MainActor
    static func live(_ thunderState: ThunderIDState, attribute: String, flowHandle: String) -> VerifyAttributeEngine {
        let client = thunderState.client
        return VerifyAttributeEngine(
            loadSchema: { try await thunderState.getUserSchema() },
            start: { try await client.verifyAttribute(attribute, handle: flowHandle) },
            submit: { try await client.verifyAttribute(payload: $0) },
            readProfile: {
                let profile = try await client.getUserProfile()
                thunderState.mergeUserProfile(profile)
                return profile
            }
        )
    }
}

/// Lets a `BaseUserProfile` show the profile a verification inside its content read again, so a custom
/// render's status updates without a second read.
private struct VerifiedProfileSinkKey: EnvironmentKey {
    static let defaultValue: ((ThunderID.UserProfile?) -> Void)? = nil
}

extension EnvironmentValues {
    var verifiedProfileSink: ((ThunderID.UserProfile?) -> Void)? {
        get { self[VerifiedProfileSinkKey.self] }
        set { self[VerifiedProfileSinkKey.self] = newValue }
    }
}

/// State passed to the ``BaseVerifyAttribute`` builder. Steps come from the server's response.
@MainActor
public final class VerifyAttributeState: ObservableObject {
    public let attribute: String
    @Published public fileprivate(set) var attributeDisplayName: String
    @Published public private(set) var phase: VerifyAttributePhase = .loading
    /// The step's components, without the heading and subheading ``title`` and ``subtitle`` replace.
    @Published public private(set) var components: [FlowComponent] = []
    @Published public private(set) var inputs: [FlowInput] = []
    @Published public private(set) var actions: [FlowAction] = []
    /// The step's `additionalData`. A rejected code comes back without it, so the masked destination, the
    /// channel and the code length of the step that sent the code are kept; nothing else carries over.
    @Published public private(set) var additionalData: [String: AnyCodable] = [:]
    @Published public private(set) var error: String?
    @Published public private(set) var fieldErrors: [String: String] = [:]
    @Published public private(set) var isLoading = false
    @Published public private(set) var loadingActionId: String?
    @Published public fileprivate(set) var templateResolver: FlowTemplateResolver?
    @Published private var heading: FlowComponent?
    @Published private var subheading: FlowComponent?

    var engine: VerifyAttributeEngine?
    var resolve: (String) -> String = { $0 }
    var onComplete: (() -> Void)?
    var onDone: (() -> Void)?
    var onError: ((Error) -> Void)?
    /// Closes the verification. `nil` when the app gave no `onCancel`.
    public internal(set) var onCancel: (() -> Void)?
    /// Receives the profile read again after the verification, or `nil` when the read failed.
    var onProfileRead: ((ThunderID.UserProfile?) -> Void)?

    private let displayNameOverride: String?
    @Published private var fieldValues: [String: String] = [:]
    private var flowId: String?
    private var challengeToken: String?
    /// Starting sends a code or a link, so it runs once per showing and never again on its own.
    private(set) var hasStarted = false

    init(attribute: String, attributeDisplayName: String?, onCancel: (() -> Void)? = nil) {
        self.attribute = attribute
        self.displayNameOverride = attributeDisplayName
        self.onCancel = onCancel
        self.attributeDisplayName = attributeDisplayName ?? titleCasedCredential(attribute)
    }

    /// The masked email address or phone number the code or link went to.
    public var destination: String? {
        guard let value = additionalData[AttributeVerification.maskedDestinationKey]?.value as? String,
              !value.isEmpty else { return nil }
        return value
    }

    /// The length of the code that was sent.
    public var codeLength: Int? {
        switch additionalData[AttributeVerification.codeLengthKey]?.value {
        case let length as Int: return length
        case let length as String: return Int(length)
        default: return nil
        }
    }

    /// A step with nothing to enter and nothing to submit waits for a link the user opens outside the app.
    public var isAwaitingLink: Bool {
        guard phase == .active else { return false }
        let hasInput = !inputs.isEmpty || !FlowComponentMerging.inputNames(in: components).isEmpty
        let hasAction = !actions.isEmpty || Self.containsAction(components)
        return !hasInput && !hasAction
    }

    public var title: String {
        text(heading?.label) ?? substitute(resolve("verifyAttribute.heading"), ["attribute": attributeDisplayName])
    }

    /// The flow's own prompt. When the flow has none, the bundle's prompt, naming where the code or link
    /// went when the server reported it.
    public var subtitle: String {
        if let flowSubtitle = text(subheading?.label) { return flowSubtitle }
        guard let destination else { return resolve("verifyAttribute.subheading.generic") }
        let key = isAwaitingLink ? "verifyAttribute.subheading.link" : "verifyAttribute.subheading"
        return substitute(resolve(key), ["destination": destination])
    }

    /// Where the code or link went, shown beside the flow's own prompt. `nil` when the server did not report
    /// it, or when ``subtitle`` already names it.
    public var destinationMessage: String? {
        guard let destination, text(subheading?.label) != nil else { return nil }
        return substitute(resolve("verifyAttribute.destination"), ["destination": destination])
    }

    public var successMessage: String {
        substitute(resolve("verifyAttribute.success"), ["attribute": attributeDisplayName])
    }

    public func binding(for name: String) -> Binding<String> {
        Binding(get: { self.fieldValues[name] ?? "" }, set: { value in
            self.fieldValues[name] = value
            if self.fieldErrors[name] != nil {
                self.fieldErrors[name] = value.trimmingCharacters(in: .whitespaces).isEmpty
                    ? self.resolve("verifyAttribute.required") : nil
            }
        })
    }

    /// Resolves a server label, or `nil` when it is empty or a template that could not be resolved.
    public func text(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = templateResolver?.resolve(raw) ?? raw
        return value.isEmpty || value.contains("{{") ? nil : value
    }

    /// Submits the step's action with its inputs, after checking the required ones are filled.
    public func submit(actionId: String) {
        Task { await performSubmit(actionId: actionId) }
    }

    /// Asks for a new code: submits the resend action with no inputs and without validation, so it works
    /// with the code field empty or partly typed.
    public func resend(actionId: String) {
        Task { await send(actionId: actionId, inputs: [:]) }
    }

    /// The user opened the link: reads the profile once, which carries the recorded verification.
    public func done() {
        Task { await performDone() }
    }

    // MARK: - Driving the flow

    func start() async {
        guard !hasStarted, let engine else { return }
        hasStarted = true
        phase = .loading
        do {
            let schema = try await engine.loadSchema()
            if displayNameOverride == nil, let name = schema[attribute]?.displayName, !name.isEmpty {
                attributeDisplayName = name
            }
            guard AttributeVerification.isVerifiableAttribute(attribute, in: schema) else {
                fail(ThunderIDError(
                    code: .invalidInput,
                    message: "Only a top-level, single-valued email or mobile attribute can be verified"
                ))
                return
            }
            await handle(try await engine.start())
        } catch {
            fail(error)
        }
    }

    func performSubmit(actionId: String) async {
        guard phase == .active, !isLoading else { return }
        let missing = inputs
            .filter { $0.required == true && (fieldValues[$0.name] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
            .map(\.name)
        guard missing.isEmpty else {
            fieldErrors = Dictionary(uniqueKeysWithValues: missing.map { ($0, resolve("verifyAttribute.required")) })
            return
        }
        await send(actionId: actionId, inputs: fieldValues.filter { !$0.value.isEmpty })
    }

    func send(actionId: String, inputs: [String: String]) async {
        guard phase == .active, !isLoading, let engine else { return }
        isLoading = true
        loadingActionId = actionId
        error = nil
        fieldErrors = [:]
        defer {
            fieldValues = [:]
            isLoading = false
            loadingActionId = nil
        }
        do {
            let payload = EmbeddedSignInPayload(
                flowId: flowId,
                actionId: actionId,
                inputs: inputs,
                challengeToken: challengeToken
            )
            await handle(try await engine.submit(payload))
        } catch {
            fail(error)
        }
    }

    func performDone() async {
        guard let engine, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        // Read even without a callback, so the signed-in user's state shows the new status.
        let profile = try? await engine.readProfile()
        onProfileRead?(profile)
        onDone?()
    }

    func handle(_ response: EmbeddedFlowResponse) async {
        switch response.flowStatus {
        case .error:
            // The client raises an ERROR step as `verificationFailed`; reported the same way here.
            fail(ThunderIDError(code: .verificationFailed, message: "The server refused the verification"))
        case .complete:
            error = nil
            phase = .complete
            // The verification is recorded on the server; the profile carries it. Read even without a
            // callback, so the signed-in user's state shows the new status.
            let profile = try? await engine?.readProfile()
            onProfileRead?(profile)
            onComplete?()
        case .promptOnly:
            update(from: response)
        }
    }

    private func update(from response: EmbeddedFlowResponse) {
        flowId = response.flowId ?? flowId
        if let token = response.challengeToken {
            challengeToken = token
        }
        let split = Self.splitHeadings(response.data?.meta?.components ?? [])
        heading = split.heading
        subheading = split.subheading
        components = split.rest
        inputs = response.data?.inputs ?? []
        actions = FlowComponentMerging.enrichActions(response.data?.actions ?? [], with: components)
        let current = response.data?.additionalData ?? [:]
        let carried = additionalData.filter { AttributeVerification.carriedForwardKeys.contains($0.key) }
        additionalData = current.merging(carried) { fromStep, _ in fromStep }
        let names = Set(inputs.map(\.name)).union(FlowComponentMerging.inputNames(in: components))
        fieldValues = Dictionary(uniqueKeysWithValues: names.map { ($0, "") })
        error = response.error == nil ? nil : flowErrorMessage(response)
        phase = .active
    }

    private func fail(_ caught: Error) {
        // An API error body is not meant for the user, so the message is generic.
        error = resolve("verifyAttribute.error")
        phase = .failed
        onError?(caught)
    }

    private func flowErrorMessage(_ response: EmbeddedFlowResponse) -> String {
        templateResolver?.translate(response.error?.message)
            ?? resolve("verifyAttribute.error")
    }

    private func substitute(_ template: String, _ values: [String: String]) -> String {
        values.reduce(template) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }

    struct StepHeadings {
        let heading: FlowComponent?
        let subheading: FlowComponent?
        let rest: [FlowComponent]
    }

    /// The first two top-level heading `TEXT` components become the title and subtitle.
    static func splitHeadings(_ components: [FlowComponent]) -> StepHeadings {
        var headings: [FlowComponent] = []
        var rest: [FlowComponent] = []
        for component in components {
            if headings.count < 2, component.type == "TEXT", component.variant?.hasPrefix("HEADING_") == true {
                headings.append(component)
            } else {
                rest.append(component)
            }
        }
        return StepHeadings(heading: headings.first, subheading: headings.dropFirst().first, rest: rest)
    }

    static func containsAction(_ components: [FlowComponent]) -> Bool {
        components.contains { ["ACTION", "RESEND"].contains($0.type) || containsAction($0.components ?? []) }
    }
}

/// Unstyled base variant (spec §8.3). Verifies one of the signed-in user's attributes by running a
/// `SELF_SERVICE` flow, and hands its ``VerifyAttributeState`` to a caller-supplied builder.
///
/// It waits for the user schema and refuses, without a request, an attribute the schema does not declare
/// as a top-level `email` or `mobile` property. Starting sends a code or a link, so it starts once per
/// showing and never retries on its own: give each attribute its own view identity (`.id(attribute)`).
/// After `COMPLETE`, and on Done after a link, it reads the profile again into the shared state, then calls
/// the callback. A refusal reaches `onError` as `verificationFailed`.
///
/// The `content` closure draws the whole step from the state: the components or inputs and actions, a
/// ``VerifyAttributeState/binding(for:)`` per field, ``VerifyAttributeState/submit(actionId:)``,
/// ``VerifyAttributeState/resend(actionId:)``, ``VerifyAttributeState/done()`` and ``VerifyAttributeState/onCancel``,
/// the destination, loading, the translated error and the phase. Starting, the profile read and the callbacks
/// stay with the component.
public struct BaseVerifyAttribute<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    @Environment(\.verifiedProfileSink) private var profileSink
    public let attribute: String
    public let flowHandle: String
    public let onComplete: (() -> Void)?
    public let onDone: (() -> Void)?
    public let onCancel: (() -> Void)?
    public let onError: ((Error) -> Void)?
    public let content: (VerifyAttributeState) -> Content
    let onProfileRead: ((ThunderID.UserProfile?) -> Void)?

    @StateObject private var state: VerifyAttributeState

    public init(
        attribute: String,
        flowHandle: String = AttributeVerification.defaultFlowHandle,
        attributeDisplayName: String? = nil,
        onComplete: (() -> Void)? = nil,
        onDone: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onError: ((Error) -> Void)? = nil,
        @ViewBuilder content: @escaping (VerifyAttributeState) -> Content
    ) {
        self.init(
            attribute: attribute,
            flowHandle: flowHandle,
            attributeDisplayName: attributeDisplayName,
            onComplete: onComplete,
            onDone: onDone,
            onCancel: onCancel,
            onError: onError,
            onProfileRead: nil,
            content: content
        )
    }

    /// Also hands the profile read again to `onProfileRead`, so the styled `UserProfile` shows it without a
    /// second read.
    init(
        attribute: String,
        flowHandle: String,
        attributeDisplayName: String?,
        onComplete: (() -> Void)?,
        onDone: (() -> Void)?,
        onCancel: (() -> Void)?,
        onError: ((Error) -> Void)?,
        onProfileRead: ((ThunderID.UserProfile?) -> Void)?,
        @ViewBuilder content: @escaping (VerifyAttributeState) -> Content
    ) {
        self.attribute = attribute
        self.flowHandle = flowHandle
        self.onComplete = onComplete
        self.onDone = onDone
        self.onCancel = onCancel
        self.onError = onError
        self.onProfileRead = onProfileRead
        self.content = content
        _state = StateObject(wrappedValue: VerifyAttributeState(
            attribute: attribute,
            attributeDisplayName: attributeDisplayName,
            onCancel: onCancel
        ))
    }

    public var body: some View {
        content(state)
            .task(id: thunderState.isInitialized) {
                guard thunderState.isInitialized else { return }
                wire()
                await state.start()
            }
            .task(id: thunderState.isInitialized) {
                await loadFlowMeta()
            }
    }

    private func wire() {
        state.engine = .live(thunderState, attribute: attribute, flowHandle: flowHandle)
        state.resolve = i18n.resolve
        state.onComplete = onComplete
        state.onDone = onDone
        state.onCancel = onCancel
        state.onError = onError
        // A verification inside a `BaseUserProfile` hands it the profile it read again.
        state.onProfileRead = onProfileRead ?? profileSink
    }

    /// Flow labels are `{{ t(...) }}` templates resolved from `GET /flow/meta` for the app's `applicationId`,
    /// as sign-up does. Without one, or when the fetch fails, the bundle's own strings stand in.
    private func loadFlowMeta() async {
        guard thunderState.isInitialized,
              let applicationId = try? thunderState.client.getConfiguration().applicationId,
              let meta = try? await thunderState.client.getFlowMeta(
                applicationId: applicationId,
                language: i18n.activeLocale
              ) else { return }
        state.templateResolver = FlowTemplateResolver(meta: meta)
    }
}
