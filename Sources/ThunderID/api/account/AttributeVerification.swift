// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Wire names and eligibility rules for self user attribute verification.
public enum AttributeVerification {
    /// Handle of the self attribute verification flow the server ships, used unless the app names another.
    public static let defaultFlowHandle = "default-self-attribute-verification-flow"
    /// Flow input naming the attribute to verify on the initiating request.
    public static let attributeInput = "attribute"
    /// `additionalData` key carrying the masked destination the code or link was sent to.
    public static let maskedDestinationKey = "maskedDestination"
    /// `additionalData` key carrying the length of the code that was sent.
    public static let codeLengthKey = "otpLength"
    /// `additionalData` key carrying the channel the code or link was sent on.
    public static let channelKey = "channel"
    /// The `additionalData` keys a later step keeps from the step that sent the code, since a rejected code
    /// comes back without them. Every other key comes from the current step only.
    public static let carriedForwardKeys: Set<String> = [maskedDestinationKey, channelKey, codeLengthKey]
    /// Schema property types whose verification status is shown, and which the user can verify.
    public static let verifiableAttributeTypes: Set<String> = ["email", "mobile"]
    /// Schema property types whose changed value opens verification after a save. Mobile is verified on
    /// request only, since sending an SMS needs a provider the deployment may not have.
    public static let verifyAfterSaveAttributeTypes: Set<String> = ["email"]

    /// Whether `attribute` is a top-level, single-valued property of type `email` or `mobile` in the user
    /// type schema from `GET /users/me/meta`.
    ///
    /// Schema keys are top-level properties, and a multi-valued property has type `array`, so the property's
    /// own type settles both. An absent schema, or one without the attribute, leaves the type unknown and
    /// resolves to `false`, so no verification starts on missing information.
    public static func isVerifiableAttribute(_ attribute: String, in schema: [String: AttributeSchema]?) -> Bool {
        isVerifiableType(schema?[attribute]?.type)
    }

    /// Whether a schema property of `type` shows a verification status and can be verified.
    public static func isVerifiableType(_ type: String?) -> Bool {
        guard let type else { return false }
        return verifiableAttributeTypes.contains(type.lowercased())
    }

    /// Whether a changed value of a schema property of `type` opens verification after it is saved.
    public static func opensAfterSave(_ type: String?) -> Bool {
        guard let type else { return false }
        return verifyAfterSaveAttributeTypes.contains(type.lowercased())
    }
}

/// The verification record of one of the user's attributes, as `GET /users/me` returns it.
public struct VerifiedAttribute: Codable, Equatable {
    /// When the attribute's current value was verified, as an RFC 3339 timestamp.
    public let verifiedAt: String?

    public init(verifiedAt: String? = nil) {
        self.verifiedAt = verifiedAt
    }
}
