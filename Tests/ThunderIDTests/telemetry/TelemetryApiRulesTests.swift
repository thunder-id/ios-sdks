// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class TelemetryApiRulesTests: XCTestCase {
    private let api = "https://api.example.com"
    private let uuid = "019a2b3c-4d5e-7f60-8a9b-0c1d2e3f4a5b"
    private let rules = TelemetryApiRules(bases: ["https://api.example.com", "https://env.example.com/v1"])
    /// The same API with the words the rules cannot tell from a path alone configured.
    private let configured = TelemetryApiRules(
        bases: ["https://api.example.com"],
        kinds: ["connections"],
        addressWords: ["tree"],
        actions: ["suspend"]
    )

    private func configured(_ method: String, _ path: String) -> TelemetryApiCall? {
        configured.classify(method: method, url: URL(string: api + path))
    }

    private func classify(_ method: String, _ url: String?) -> TelemetryApiCall? {
        rules.classify(method: method, url: url.flatMap(URL.init(string:)))
    }

    private func name(_ method: String, _ path: String) -> String? {
        classify(method, api + path)?.name
    }

    func testNamesCreatesUpdatesAndDeletesFromTheCollectionWithAPathTemplate() {
        XCTAssertEqual(
            classify("POST", "\(api)/applications"),
            TelemetryApiCall(name: "application.create", route: "/applications", data: ["resource_type": "application"])
        )
        XCTAssertEqual(
            classify("DELETE", "\(api)/roles/\(uuid)"),
            TelemetryApiCall(name: "role.delete", route: "/roles/{id}", data: ["resource_type": "role"])
        )
        XCTAssertEqual(name("PATCH", "/organization-units/\(uuid)"), "organization-unit.update")
        XCTAssertEqual(name("PUT", "/variables/API_KEY"), "variable.update")
        XCTAssertEqual(name("DELETE", "/secrets"), "secret.delete")
    }

    func testNamesEveryKindOfResourceTheSameWayWhateverTheShapeOfItsPath() {
        let cases: [(String, String, String, [String: String])] = [
            ("POST", "/connections/google", "connection.create", ["resource_type": "connection"]),
            ("PUT", "/connections/sms-gateway/\(uuid)", "connection.update", ["resource_type": "connection"]),
            ("POST", "/design/themes", "theme.create", ["resource_type": "theme"]),
            (
                "DELETE",
                "/openid4vci/credential-configurations/\(uuid)",
                "credential-configuration.delete",
                ["resource_type": "credential-configuration"]
            ),
            ("POST", "/scim/v2/Users", "user.create", ["resource_type": "user"]),
            ("PUT", "/server-config/branding", "server-config.update", ["resource_type": "server-config"]),
            (
                "POST",
                "/resource-servers/\(uuid)/resources/\(uuid)/actions",
                "action.create",
                ["parent_type": "resource", "resource_type": "action"]
            ),
            (
                "POST",
                "/notification-templates/email/templates",
                "template.create",
                ["parent_type": "notification-template", "resource_type": "template"]
            ),
            (
                "PUT",
                "/organization-units/tree/engineering/backend",
                "organization-unit.update",
                ["resource_type": "organization-unit"]
            ),
            ("PUT", "/users/me", "user.update", ["resource_type": "user"])
        ]
        for (method, path, expected, data) in cases {
            let call = classify(method, api + path)
            XCTAssertEqual(call?.name, expected, path)
            XCTAssertEqual(call?.data, data, path)
        }
    }

    func testNamesASubResourceForItselfWithItsParentUnlessConfiguredAsAParentAction() {
        XCTAssertEqual(
            classify("POST", "\(api)/applications/\(uuid)/sharing-policies"),
            TelemetryApiCall(
                name: "sharing-policy.create",
                route: "/applications/{id}/sharing-policies",
                data: ["parent_type": "application", "resource_type": "sharing-policy"]
            )
        )
        let configured = TelemetryApiRules(
            bases: [api],
            parentActions: ["sharing-policies": [.create: "share", .delete: "unshare", .update: "share-update"]],
            kinds: ["connections"]
        )
        XCTAssertEqual(
            configured.classify(method: "POST", url: URL(string: "\(api)/applications/\(uuid)/sharing-policies")),
            TelemetryApiCall(
                name: "application.share",
                route: "/applications/{id}/sharing-policies",
                data: ["resource_type": "application"]
            )
        )
        XCTAssertEqual(
            configured.classify(method: "PUT", url: URL(string: "\(api)/roles/\(uuid)/sharing-policies/\(uuid)"))?.name,
            "role.share-update"
        )
        XCTAssertEqual(
            configured.classify(
                method: "DELETE",
                url: URL(string: "\(api)/connections/oidc/\(uuid)/sharing-policies/\(uuid)")
            )?.name,
            "connection.unshare"
        )
        // Without `kinds`, the word after `connections` is an item value and the rest its address.
        XCTAssertEqual(
            classify("DELETE", "\(api)/connections/oidc/\(uuid)/sharing-policies/\(uuid)"),
            TelemetryApiCall(
                name: "connection.delete",
                route: "/connections/{id}/{path}",
                data: ["resource_type": "connection"]
            )
        )
    }

    func testNamesActionsOnAResourceForWhatTheyActOn() {
        XCTAssertEqual(
            name("POST", "/applications/\(uuid)/client-secret/regenerate"),
            "application.client-secret-regenerate"
        )
        XCTAssertEqual(name("POST", "/users/\(uuid)/update-credentials"), "user.update-credentials")
        XCTAssertEqual(name("POST", "/flows/\(uuid)/restore"), "flow.restore")
        XCTAssertEqual(name("POST", "/users/me/agents/\(uuid)/suspend"), "agent.suspend")
        XCTAssertEqual(name("PUT", "/projects/\(uuid)/auto-sync"), "project.auto-sync-update")
        XCTAssertEqual(
            classify("POST", "\(api)/groups/\(uuid)/members/add"),
            TelemetryApiCall(
                name: "group.member-add",
                route: "/groups/{id}/members/add",
                data: ["resource_type": "group", "sub_type": "member"]
            )
        )
        XCTAssertEqual(name("POST", "/groups/\(uuid)/members/remove"), "group.member-remove")
        XCTAssertEqual(name("POST", "/roles/\(uuid)/assignments/add"), "role.assignment-add")
        XCTAssertEqual(name("POST", "/users/me/agents/suspend"), "agent.create")
        XCTAssertEqual(configured("POST", "/users/me/agents/suspend")?.name, "user.agent-suspend")
    }

    func testReportsAKindOnlyForAConfiguredTopLevelCollection() {
        XCTAssertEqual(
            configured("POST", "/connections/google"),
            TelemetryApiCall(
                name: "connection.create",
                route: "/connections/google",
                data: ["kind": "google", "resource_type": "connection"]
            )
        )
        XCTAssertEqual(
            configured("PUT", "/connections/sms-gateway/\(uuid)"),
            TelemetryApiCall(
                name: "connection.update",
                route: "/connections/sms-gateway/{id}",
                data: ["kind": "sms-gateway", "resource_type": "connection"]
            )
        )
        XCTAssertEqual(
            classify("POST", "\(api)/connections/google"),
            TelemetryApiCall(name: "connection.create", route: "/connections/{id}", data: ["resource_type": "connection"])
        )
        XCTAssertEqual(
            configured("POST", "/users/alice"),
            TelemetryApiCall(name: "user.create", route: "/users/{id}", data: ["resource_type": "user"])
        )
        // Under a sub-collection a word is never a kind, even of a configured collection.
        XCTAssertEqual(
            configured("POST", "/groups/\(uuid)/connections/google")?.data,
            ["parent_type": "group", "resource_type": "connection"]
        )
    }

    func testReadsEverythingAfterAConfiguredAddressWordAsAnAddress() {
        XCTAssertEqual(
            configured("PUT", "/organization-units/tree/engineering/operations"),
            TelemetryApiCall(
                name: "organization-unit.update",
                route: "/organization-units/tree/{path}",
                data: ["resource_type": "organization-unit"]
            )
        )
        XCTAssertEqual(configured("POST", "/organization-units/tree/engineering")?.name, "organization-unit.create")
        XCTAssertEqual(configured("DELETE", "/organization-units/tree/a/b/c")?.name, "organization-unit.delete")
        XCTAssertEqual(
            configured("PUT", "/organization-units/tree"),
            TelemetryApiCall(
                name: "organization-unit.update",
                route: "/organization-units/tree/{path}",
                data: ["resource_type": "organization-unit"]
            )
        )
        // Without the configuration, the word item rule keeps the address out of the name.
        XCTAssertEqual(
            classify("PUT", "\(api)/organization-units/tree/engineering/operations"),
            TelemetryApiCall(
                name: "organization-unit.update",
                route: "/organization-units/{id}/{path}",
                data: ["resource_type": "organization-unit"]
            )
        )
    }

    func testNamesAWordEndingAPostToASubCollectionAsAnActionOnlyForChangeWordsAndConfiguredActions() {
        XCTAssertEqual(name("POST", "/groups/\(uuid)/members/add"), "group.member-add")
        XCTAssertEqual(
            classify("POST", "\(api)/groups/\(uuid)/members/alice"),
            TelemetryApiCall(
                name: "member.create",
                route: "/groups/{id}/members/{id}",
                data: ["parent_type": "group", "resource_type": "member"]
            )
        )
        XCTAssertEqual(
            configured("POST", "/users/\(uuid)/agents/suspend"),
            TelemetryApiCall(
                name: "user.agent-suspend",
                route: "/users/{id}/agents/suspend",
                data: ["resource_type": "user", "sub_type": "agent"]
            )
        )
        XCTAssertEqual(name("POST", "/users/\(uuid)/agents/suspend"), "agent.create")
    }

    func testReadsThePathBelowTheLongestMatchingBase() {
        let nested = TelemetryApiRules(bases: [api, "\(api)/admin"])
        XCTAssertEqual(
            nested.classify(method: "POST", url: URL(string: "\(api)/admin/widgets")),
            TelemetryApiCall(name: "widget.create", route: "/widgets", data: ["resource_type": "widget"])
        )
        XCTAssertEqual(nested.literalPath(URL(string: "\(api)/admin/Widgets/W1")!), "/widgets/w1")
    }

    func testNamesAnActionOnAnItemFromItsWordsAndKeepsWordsAfterAWordItemOutOfTheName() {
        XCTAssertEqual(name("POST", "/gateways/\(uuid)/apply"), "gateway.apply")
        XCTAssertEqual(name("POST", "/gateways/\(uuid)/revert"), "gateway.revert")
        XCTAssertEqual(
            classify("POST", "https://env.example.com/v1/environments/dev/apply"),
            TelemetryApiCall(
                name: "environment.create",
                route: "/environments/{id}/{path}",
                data: ["resource_type": "environment"]
            )
        )
        XCTAssertEqual(name("POST", "/promotions"), "promotion.create")
    }

    func testNamesACallWithNoResourceTypeFromItsWords() {
        XCTAssertEqual(classify("POST", "\(api)/import"), TelemetryApiCall(name: "api.import", route: "/import", data: [:]))
        XCTAssertEqual(name("POST", "/import/managed"), "api.import-managed")
        XCTAssertEqual(name("POST", "/export"), "api.export")
        XCTAssertEqual(name("DELETE", "/maintenance"), "api.maintenance-delete")
        XCTAssertEqual(
            classify("PUT", "\(api)/dcr/register/c1d2e3f4a5b6c7d8e9f0"),
            TelemetryApiCall(name: "api.call", route: "/dcr/{id}/{id}", data: ["method": "PUT"])
        )
    }

    func testReportsAnyOtherChangeAsApiCallKeepingOnlyTheFirstSegment() {
        XCTAssertEqual(
            classify("POST", "\(api)/import/\(uuid)/retry-later"),
            TelemetryApiCall(name: "api.call", route: "/import/{id}/{id}", data: ["method": "POST"])
        )
        XCTAssertEqual(
            classify("POST", "\(api)/import/v2/\(uuid)/retry-later/x1")?.route,
            "/import/{id}/{id}/{id}/{id}"
        )
        XCTAssertEqual(classify("DELETE", "\(api)/\(uuid)/x")?.route, "/{id}/{id}")
    }

    func testSkipsALabelAndItsValueInFrontOfASubCollection() {
        XCTAssertEqual(
            classify("DELETE", "\(api)/i18n/languages/en/translations/ns/auth/keys/login.title"),
            TelemetryApiCall(
                name: "key.delete",
                route: "/i18n/languages/{id}/translations/ns/{id}/keys/{id}",
                data: ["parent_type": "translation", "resource_type": "key"]
            )
        )
        XCTAssertEqual(name("POST", "/i18n/languages/en/translations/ns/auth/keys/login.title"), "key.create")
        XCTAssertEqual(name("POST", "/i18n/languages/en/translations/ns/auth/keys"), "key.create")
    }

    func testNamesOnlyChangesAndOnlyOnAWatchedApi() {
        XCTAssertNil(name("GET", "/applications"))
        XCTAssertNil(name("HEAD", "/applications"))
        XCTAssertNil(name("OPTIONS", "/applications"))
        XCTAssertNil(classify("POST", "https://other.example.com/applications"))
        XCTAssertNil(classify("POST", nil))
        XCTAssertNil(classify("POST", "https://env.example.com/applications"))
        XCTAssertNil(classify("POST", "https://api.example.com:8443/applications"))
    }

    func testTreatsTheDefaultPortAsTheSameOrigin() {
        XCTAssertEqual(classify("POST", "https://api.example.com:443/applications")?.name, "application.create")
    }

    func testReadsOnlyWhetherABodySetsAField() {
        let body = Data(#"{"dryRun":true,"preview":false,"origin":"","count":0,"note":null}"#.utf8)
        XCTAssertTrue(TelemetryApiRules.sets(body, "dryRun"))
        XCTAssertFalse(TelemetryApiRules.sets(body, "preview"))
        XCTAssertFalse(TelemetryApiRules.sets(body, "origin"))
        XCTAssertTrue(TelemetryApiRules.sets(body, "count"))
        XCTAssertFalse(TelemetryApiRules.sets(body, "note"))
        XCTAssertFalse(TelemetryApiRules.sets(body, "missing"))
        XCTAssertFalse(TelemetryApiRules.sets(nil, "dryRun"))
    }

    func testReportsAFailureWithItsStatusAndOnlyAWellFormedErrorCode() {
        XCTAssertEqual(
            TelemetryApiRules.failureData(
                status: 409,
                responseBody: Data(#"{"code":"APP-1023","message":"Name \"x\" taken"}"#.utf8)
            ),
            ["error_code": "APP-1023", "status": "409"]
        )
        XCTAssertEqual(
            TelemetryApiRules.failureData(status: 500, responseBody: Data(#"{"code":"something the user typed"}"#.utf8)),
            ["status": "500"]
        )
        XCTAssertEqual(TelemetryApiRules.failureData(status: nil, responseBody: nil), ["status": "network"])
    }
}
