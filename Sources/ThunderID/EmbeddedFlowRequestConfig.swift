// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// How ``ThunderIDClient/signIn(payload:request:sessionId:)`` runs an embedded flow.
public struct EmbeddedFlowRequestConfig {
    public var applicationId: String
    public var flowType: FlowType
    /// Bounds an `AUTHENTICATION` flow to this unit: sent as `ouId` when the flow starts, never after.
    public var organizationUnitId: String?
    /// Signs the signed-in user in again after ``ThunderIDErrorCode/stepUpRequired``: the flow starts with
    /// ``maxAge`` and the kept SSO session handles, and its assertion replaces the session only for the same
    /// `sub`; another user fails with ``ThunderIDErrorCode/authenticationFailed`` and the session stays.
    public var reauthentication: Bool
    /// With ``reauthentication``: how recent, in seconds, the sign-in must be; `0` (always ask) when `nil`.
    public var maxAge: Int?

    public init(
        applicationId: String,
        flowType: FlowType = .authentication,
        organizationUnitId: String? = nil,
        reauthentication: Bool = false,
        maxAge: Int? = nil
    ) {
        self.applicationId = applicationId
        self.flowType = flowType
        self.organizationUnitId = organizationUnitId
        self.reauthentication = reauthentication
        self.maxAge = maxAge
    }
}
