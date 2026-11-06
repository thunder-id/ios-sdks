// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

@MainActor
final class ApplicationComponentTests: XCTestCase {
    private let i18n = ThunderIDI18n(language: "en-US", storageKey: "application_component_tests_locale")

    private final class Captured<Value> {
        var value: Value?
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func application(publicClient: Bool = false, readOnly: Bool = false) throws -> Application {
        try decode(
            #"{"id":"app-1","name":"Console","type":"browser","ouId":"ou-1","isReadOnly":\#(readOnly),"# +
            #""status":{"value":"ACTIVE"},"logoUrl":"https://logo","inboundAuthConfig":[{"type":"oauth2","config":"# +
            #"{"clientId":"console","publicClient":\#(publicClient),"redirectUris":["https://app/cb"],"# +
            #""grantTypes":["authorization_code","urn:ietf:params:oauth:grant-type:token-exchange"],"# +
            #""responseTypes":["code"]}}]}"#
        )
    }

    private func render(_ view: some View, state: ThunderIDState? = nil) {
        let state = state ?? ThunderIDState(client: ThunderIDClient(), i18n: i18n)
        let renderer = ImageRenderer(
            content: view
                .environmentObject(i18n)
                .environmentObject(state)
                .frame(width: 400)
        )
        XCTAssertNotNil(renderer.cgImage)
    }

    // MARK: - Strings

    func testEveryApplicationStringIsInTheBundle() {
        for key in [
            "admin.applications.list.title", "admin.applications.create.submit", "admin.applications.secret.notice",
            "admin.applications.details.delete.confirm", "admin.applications.details.secret.confirm",
            "admin.applications.grant_types.client_credentials", "admin.applications.status.suspended"
        ] {
            XCTAssertNotNil(DefaultStrings.all[key], "Missing default string for key: \(key)")
        }
        XCTAssertEqual(i18n.applicationStatus(ApplicationAccessStatus(value: "SUSPENDED")), "Suspended")
        XCTAssertEqual(i18n.grantTypeLabel("refresh_token"), "Refresh token")
        XCTAssertEqual(i18n.grantTypeLabel("urn:custom"), "urn:custom")
    }

    // MARK: - List

    func testListRendersAndHandsRowsToContent() throws {
        let page: ApplicationListResponse = try decode(
            #"{"totalResults":45,"count":1,"applications":[{"id":"app-1","name":"Console","clientId":"console","# +
            #""type":"browser","status":{"value":"SUSPENDED"}}]}"#
        )
        let captured = Captured<AdminListState<BasicApplication>>()

        render(BaseApplicationList(applications: page.applications, totalResults: 45, onPageChange: { _ in }))
        render(BaseApplicationList(applications: [], error: "Nope"))
        render(
            BaseApplicationList(
                applications: page.applications,
                offset: 20,
                totalResults: 45,
                onPageChange: { _ in },
                onSelect: { _ in }
            ) { state in
                let _ = (captured.value = state)
                Text(state.rows.map(\.name).joined())
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertEqual(state.rows.map(\.id), ["app-1"])
        XCTAssertEqual(state.rows.first?.status?.value, "SUSPENDED")
        XCTAssertEqual(state.totalResults, 45)
        XCTAssertEqual(state.offset, 20)
        XCTAssertNotNil(state.onSelect)
        XCTAssertNil(state.onSearch, "The applications API has no filter, so there is no search")
    }

    // MARK: - Create

    func testCreateFormDoesNotSubmitInvalidValues() throws {
        let captured = Captured<ApplicationCreateFormState>()
        var submissions: [ApplicationCreateSubmission] = []

        render(BaseApplicationCreate { submissions.append($0) })
        render(
            BaseApplicationCreate(onSubmit: { submissions.append($0) }) { state in
                let _ = (captured.value = state)
                TextField("Name", text: state.name)
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertFalse(state.isValid)
        XCTAssertEqual(state.grantTypes.wrappedValue, ["authorization_code", "refresh_token"])
        XCTAssertFalse(state.publicClient.wrappedValue)
        state.submit()
        XCTAssertTrue(submissions.isEmpty)
        XCTAssertNil(state.clientSecret)
    }

    func testCreateShowsTheIssuedSecretOnce() throws {
        let captured = Captured<ApplicationCreateFormState>()
        var done = 0

        render(BaseApplicationCreate(clientSecret: "s3cret", onSecretDone: { done += 1 }) { _ in })
        render(
            BaseApplicationCreate(clientSecret: "s3cret", onSecretDone: { done += 1 }, onSubmit: { _ in }) { state in
                let _ = (captured.value = state)
                Text(state.clientSecret ?? "")
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertEqual(state.clientSecret, "s3cret")
        state.onSecretDone?()
        XCTAssertEqual(done, 1)
    }

    func testOAuthBasicsValidation() {
        let code: Set<String> = ["authorization_code"]
        XCTAssertFalse(applicationOAuthIsValid(grantTypes: [], redirectUris: ["https://a"], publicClient: false))
        XCTAssertFalse(applicationOAuthIsValid(grantTypes: code, redirectUris: [], publicClient: false))
        XCTAssertTrue(applicationOAuthIsValid(grantTypes: code, redirectUris: ["https://a"], publicClient: true))
        XCTAssertFalse(applicationOAuthIsValid(grantTypes: ["client_credentials"], redirectUris: [], publicClient: true))
        XCTAssertTrue(applicationOAuthIsValid(grantTypes: ["client_credentials"], redirectUris: [], publicClient: false))
        XCTAssertEqual(applicationURIList(" https://a , ,https://b\nhttps://c "), ["https://a", "https://b", "https://c"])
    }

    func testCreateSubmissionBuildsTheRequest() throws {
        let submission = ApplicationCreateSubmission(
            name: "Console",
            description: nil,
            url: "https://app",
            logoUrl: nil,
            redirectUris: ["https://app/cb"],
            grantTypes: ["authorization_code", "refresh_token"],
            publicClient: true
        )

        let request = ApplicationRequest(submission: submission, ouId: "ou-1", type: "custom")
        let config = try XCTUnwrap(request.inboundAuthConfig?.first?.config)

        XCTAssertEqual(request.ouId, "ou-1")
        XCTAssertEqual(request.type, "custom")
        XCTAssertEqual(request.url, "https://app")
        XCTAssertEqual(config.responseTypes, ["code"])
        XCTAssertEqual(config.redirectUris, ["https://app/cb"])
        XCTAssertEqual(config.tokenEndpointAuthMethod, "none")
        XCTAssertEqual(config.pkceRequired, true)
        let confidential = OAuth2Config.basics(grantTypes: ["client_credentials"], redirectUris: [], publicClient: false)
        XCTAssertEqual(confidential.responseTypes, [])
        XCTAssertEqual(confidential.tokenEndpointAuthMethod, "client_secret_basic")
    }

    // MARK: - Details

    func testDestructiveActionsAreOffUnlessEnabled() throws {
        let details = ApplicationDetails(applicationId: "app-1")
        XCTAssertFalse(details.editable)
        XCTAssertFalse(details.deletable)
        XCTAssertFalse(details.secretRegenerable)
        XCTAssertEqual(details.administrationMode, .native)

        let state = BaseApplicationDetails(application: try application()).renderState
        XCTAssertNil(state.onDelete)
        XCTAssertNil(state.onUpdate)
        XCTAssertNil(state.onRegenerateSecret)
    }

    func testReadOnlyAndPublicApplicationsHideActions() throws {
        let readOnly = BaseApplicationDetails(
            application: try application(readOnly: true),
            onDelete: {},
            onUpdate: { _ in },
            onRegenerateSecret: {}
        ).renderState
        let publicClient = BaseApplicationDetails(
            application: try application(publicClient: true),
            onDelete: {},
            onUpdate: { _ in },
            onRegenerateSecret: {}
        ).renderState
        let confidential = BaseApplicationDetails(
            application: try application(),
            onDelete: {},
            onUpdate: { _ in },
            onRegenerateSecret: {}
        ).renderState

        XCTAssertNil(readOnly.onDelete)
        XCTAssertNil(readOnly.onUpdate)
        XCTAssertNil(readOnly.onRegenerateSecret)
        XCTAssertNotNil(publicClient.onDelete)
        XCTAssertNil(publicClient.onRegenerateSecret, "A public client has no secret")
        XCTAssertNotNil(confidential.onRegenerateSecret)
    }

    func testDetailsRenderAndHandStateToContent() throws {
        let app = try application()
        let captured = Captured<ApplicationDetailsState>()

        render(BaseApplicationDetails(application: app, onDelete: {}, onUpdate: { _ in }, onRegenerateSecret: {}))
        render(BaseApplicationDetails(application: app, clientSecret: "new-secret", onSecretDone: {}))
        render(BaseApplicationDetails(application: nil, isLoading: true))
        render(BaseApplicationDetails(application: nil, error: "Gone"))
        render(
            BaseApplicationDetails(application: app, clientSecret: "new-secret", onDelete: {}) { state in
                let _ = (captured.value = state)
                Text(state.application?.name ?? "")
            }
        )

        let state = try XCTUnwrap(captured.value)
        XCTAssertEqual(state.application?.name, "Console")
        XCTAssertEqual(state.application?.status?.value, "ACTIVE")
        XCTAssertEqual(state.clientSecret, "new-secret")
        XCTAssertNotNil(state.onDelete)
        XCTAssertNil(state.onUpdate)
    }

    func testEditKeepsWhatTheFormDoesNotOffer() throws {
        let app = try application()
        let edit = ApplicationEdit(
            name: "Console 2",
            description: "New",
            url: nil,
            logoUrl: "https://logo",
            redirectUris: ["https://app/new"],
            grantTypes: ["client_credentials"]
        )

        let request = app.request.applying(edit)
        let config = try XCTUnwrap(request.inboundAuthConfig?.first?.config)

        XCTAssertEqual(ApplicationEdit(app).grantTypes.count, 2)
        XCTAssertEqual(request.name, "Console 2")
        XCTAssertEqual(request.type, "browser")
        XCTAssertEqual(request.ouId, "ou-1")
        XCTAssertEqual(config.clientId, "console")
        XCTAssertEqual(config.redirectUris, ["https://app/new"])
        XCTAssertEqual(config.grantTypes, ["client_credentials"])
        XCTAssertEqual(config.responseTypes, [])
        render(
            ApplicationEditForm(
                i18n: i18n,
                edit: ApplicationEdit(app),
                hasOAuth: true,
                publicClient: false,
                isUpdating: false,
                onCancel: {},
                onSave: { _ in }
            )
        )
    }

    func testConnectedComponentsRenderWithoutASession() {
        render(ApplicationList())
        render(ApplicationCreate())
        render(ApplicationDetails(applicationId: "app-1", deletable: true))
    }

    // MARK: - Project placement

    /// The placement an ``AdminCreateHost`` hands its build closure on submit.
    private func placement(ouId: String?, projectScoped: Bool, project: String?) throws -> AdminPlacement? {
        let state = ThunderIDState(client: ThunderIDClient(), i18n: i18n)
        if let project {
            state.setCurrentProject(
                try decode(#"{"id":"\#(project)","handle":"shop","displayName":"Shop"}"#) as Project
            )
        }
        let host = Captured<AdminCreateContext<ApplicationRequest, Application>>()
        render(
            AdminCreateHost(
                state: state,
                ouId: ouId,
                projectScoped: projectScoped,
                mutation: state.createApplicationMutation()
            ) { context in
                let _ = (host.value = context)
                Text("")
            },
            state: state
        )
        let captured = Captured<AdminPlacement>()
        try XCTUnwrap(host.value).submit(placement: { placement in
            captured.value = placement
            return ApplicationRequest(name: "Shop")
        }) { _ in }
        return captured.value
    }

    func testCreateSendsTheCurrentProjectWhenNoOrganizationUnitIsGiven() throws {
        XCTAssertEqual(
            try placement(ouId: nil, projectScoped: true, project: "p-1"),
            AdminPlacement(ouId: nil, projectId: "p-1")
        )
        // An organization unit the app passes wins over the project.
        XCTAssertEqual(
            try placement(ouId: "ou-1", projectScoped: true, project: "p-1"),
            AdminPlacement(ouId: "ou-1", projectId: nil)
        )
        // Components other than application and agent creates never use the project.
        XCTAssertEqual(
            try placement(ouId: "ou-1", projectScoped: false, project: "p-1"),
            AdminPlacement(ouId: "ou-1", projectId: nil)
        )
        // Without a project or an organization unit, nothing is sent until the user's own unit is known.
        XCTAssertNil(try placement(ouId: nil, projectScoped: true, project: nil))
        XCTAssertNil(try placement(ouId: nil, projectScoped: false, project: "p-1"))
    }

    func testCreateRequestCarriesTheProject() throws {
        let submission = ApplicationCreateSubmission(
            name: "Shop",
            description: nil,
            url: nil,
            logoUrl: nil,
            redirectUris: [],
            grantTypes: ["client_credentials"],
            publicClient: false
        )
        let request = ApplicationRequest(submission: submission, ouId: nil, projectId: "p-1", type: "m2m")
        XCTAssertNil(request.ouId)
        XCTAssertEqual(request.projectId, "p-1")
    }
}
