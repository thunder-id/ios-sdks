// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderIDSwiftUI

extension CapabilityCatalog {
    /// The signed-in user's organization units, and switching between them.
    static let organizationSection = CapabilitySection(name: "Organizations", items: [
        Capability(
            id: .organizations,
            name: "Organizations",
            api: "getAccessibleOrganizationUnits() · getCurrentOrganizationUnit()",
            mode: .automatic
        ),
        Capability(
            id: .organizationSwitch,
            name: "Switch organization",
            api: "switchOrganizationUnit(_:options:)",
            mode: .interactive
        )
    ])

    /// The optional grants: pushed authorization requests, CIBA and device authorization.
    static let grantSection = CapabilitySection(name: "Grants", items: [
        Capability(
            id: .pushedAuthorization,
            name: "Pushed authorization request",
            api: "signInURL(options:) · pushedAuthorizationRequests",
            mode: .automatic
        ),
        Capability(
            id: .ciba,
            name: "Backchannel sign-in (CIBA)",
            api: "initiateCIBA(options:) · pollCIBA(authReqId:interval:)",
            mode: .interactive
        ),
        Capability(
            id: .deviceAuthorization,
            name: "Device authorization",
            api: "startDeviceAuthorization() · verifyDeviceCode(userCode:)",
            mode: .automatic
        )
    ])
}

extension CheckContext {
    static let organizationRunners: [CapabilityID: Runner] = [
        .organizations: { try await $0.organizations() },
        .organizationSwitch: { try await $0.switchOrganization() },
        .pushedAuthorization: { try await $0.pushedAuthorization() },
        .ciba: { try await $0.ciba() },
        .deviceAuthorization: { try await $0.deviceAuthorization() }
    ]

    func organizations() async throws -> String {
        try await requireSignedIn()
        let list = try await client.getAccessibleOrganizationUnits(limit: 20)
        let current = try await client.getCurrentOrganizationUnit()
        log.record("ous:loaded", "count=\(list.totalResults) current=\(list.current)", kind: .success)
        let name = current?.name ?? current?.handle ?? list.current
        return "\(list.totalResults) accessible units; signed in to \(name)"
    }

    /// Switches to another accessible unit: silently with a device secret, through the browser in redirect
    /// mode, or by starting the unit-bounded flow in app-native mode.
    func switchOrganization() async throws -> String {
        try await requireSignedIn()
        let list = try await client.getAccessibleOrganizationUnits(limit: 20)
        guard let target = list.organizationUnits.first(where: { $0.id != list.current }) else {
            throw CheckFailure("The user can access no other organization unit")
        }
        var options = SwitchOrganizationUnitOptions(applicationId: config.applicationId)
        if config.clientId != nil, let scheme = config.callbackScheme {
            options.authorize = { url in
                try await FederatedAuthSession().authenticate(url: url, callbackURLScheme: scheme)
            }
        }
        switch try await client.switchOrganizationUnit(target.id, options: options) {
        case .switched(let user):
            await state.refresh()
            let ouId = user.claims["ouId"]?.value as? String ?? "?"
            log.record("ou:switched", "ouId=\(ouId)", kind: .success)
            return "Switched to \(target.name)"
        case .signInRequired(let response):
            log.record("ou:signInRequired", "step=\(response.stepId ?? "?")")
            return "Sign-in to \(target.name) needs the user: show SignIn(organizationUnitId:)"
        }
    }

    func pushedAuthorization() async throws -> String {
        guard config.clientId != nil else { throw CheckFailure("Set THUNDERID_CLIENT_ID in Config.plist") }
        let url = try await client.signInURL()
        let pushed = url.query?.contains("request_uri=") == true
        log.record("par:checked", pushed ? "pushed" : "not required", kind: .success)
        return pushed
            ? "The authorization request was pushed; the URL carries only request_uri"
            : "The server does not require PAR; set pushedAuthorizationRequests to push anyway"
    }

    /// Starts a backchannel sign-in for the signed-in user and waits for the approval on their device.
    func ciba() async throws -> String {
        try await requireSignedIn()
        let user = try await client.getUser()
        guard let hint = user.username ?? user.email else { throw CheckFailure("The user has no login hint") }
        let request = try await client.initiateCIBA(options: CIBAInitiateOptions(
            loginHint: hint,
            bindingMessage: "ThunderID Playground"
        ))
        log.record("ciba:initiated", "expiresIn=\(request.expiresIn)")
        _ = try await client.pollCIBA(authReqId: request.authReqId, interval: request.interval)
        await state.refresh()
        log.record("ciba:approved", kind: .success)
        return "Approved on the user's device"
    }

    /// Plays both sides: this app asks for a device code, then starts the DEVICE_GRANT flow with it.
    func deviceAuthorization() async throws -> String {
        let device = try await client.startDeviceAuthorization()
        log.record("device:started", "userCode=\(device.userCode)")
        guard config.applicationId != nil else {
            return "User code \(device.userCode); set THUNDERID_APPLICATION_ID to verify it in-app"
        }
        let verification = try await client.verifyDeviceCode(userCode: device.userCode)
        log.record("device:verify", "step=\(verification.flow.stepId ?? "?")", kind: .success)
        return "User code \(device.userCode); DEVICE_GRANT flow at \(verification.flow.stepId ?? "completion")"
    }
}
