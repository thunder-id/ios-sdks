// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// What the administrator-initiated verification flow reports once it has sent the link. It never
/// carries the link or the address.
public struct UserAttributeVerificationResult: Equatable {
    /// The channel the link went out on, such as `email`.
    public let channel: String
    /// Whether the flow's email step sent the link. `nil` when the flow does not report it.
    public let emailSent: Bool?
    /// The masked address the link was sent to, such as `j***@example.com`.
    public let maskedDestination: String?

    public init(channel: String, emailSent: Bool? = nil, maskedDestination: String? = nil) {
        self.channel = channel
        self.emailSent = emailSent
        self.maskedDestination = maskedDestination
    }
}

/// The body of `POST /flow/execute` that starts an administrator-initiated flow.
struct AdminInitiatedFlowRequest: Encodable {
    let flowType = FlowType.adminInitiated.rawValue
    let handle: String
    let inputs: [String: String]
    let verbose = true
}

public extension UsersAPI {
    // MARK: - Verification

    /// Sends a user a link to verify one of their attributes, through the server's administrator-initiated
    /// verification flow. The flow pauses once the link is sent; the user finishes it from the link,
    /// without the administrator. The request goes to `{baseUrl}/flow/execute` with the administrator's
    /// token.
    ///
    /// - Parameters:
    ///   - id: The user's identifier.
    ///   - attribute: The attribute to verify, such as `email`.
    ///   - handle: Handle of the administrator-initiated verification flow to run.
    /// - Returns: The channel and the masked destination the link was sent to.
    /// - Throws: ``ThunderIDErrorCode/invalidInput`` before any request when `id` or `attribute` is blank;
    ///   ``ThunderIDErrorCode/administrationFlowFailed`` when a step refuses, with the step's error (such
    ///   as `FET-1114` for a suspended user) as ``ThunderIDError/flowError``, or when the flow reports no
    ///   sent link; the usual API errors when the server refuses the request.
    func sendAttributeVerification(
        id: String,
        attribute: String,
        handle: String = AttributeVerification.adminFlowHandle,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> UserAttributeVerificationResult {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !attribute.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ThunderIDError(code: .invalidInput, message: "A user identifier and an attribute are required.")
        }
        try transport.requireFlowBaseUrl()
        let request = AdminInitiatedFlowRequest(
            handle: handle,
            inputs: [AttributeVerification.attributeInput: attribute, AttributeVerification.subjectInput: id]
        )
        var sensitiveTransport = transport
        sensitiveTransport.isSensitive = true
        let result: AdministrationFlowExecutionResponse = try await sensitiveTransport.server(
            method: "POST",
            path: "flow/execute",
            body: try JSONEncoder().encode(request),
            fetcher: fetcher
        )
        return try Self.sentVerification(from: result)
    }
}

extension UsersAPI {
    /// Reads the sent link from the flow's response: `INCOMPLETE` with a channel, else a refusal.
    static func sentVerification(from result: AdministrationFlowExecutionResponse) throws
        -> UserAttributeVerificationResult {
        let data = result.data?.additionalData ?? [:]
        if result.flowStatus == "INCOMPLETE", let channel = data[AttributeVerification.channelKey], !channel.isEmpty {
            let maskedDestination = data[AttributeVerification.maskedDestinationKey]
            return UserAttributeVerificationResult(
                channel: channel,
                emailSent: data[AdministrationFlowData.emailSent].map { $0 == "true" },
                maskedDestination: maskedDestination?.isEmpty == false ? maskedDestination : nil
            )
        }
        if result.flowStatus == "ERROR" {
            let flowError = result.error ?? FlowError()
            throw ThunderIDError(
                code: .administrationFlowFailed,
                message: flowError.message?.defaultValue ?? flowError.description?.defaultValue
                    ?? "The verification link was not sent.",
                flowError: flowError
            )
        }
        throw ThunderIDError(
            code: .administrationFlowFailed,
            message: "The verification flow did not report a sent link."
        )
    }
}
