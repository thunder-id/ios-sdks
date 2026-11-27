// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Records what the telemetry sends.
final class TelemetrySink: @unchecked Sendable {
    private let lock = NSLock()
    private var _bodies: [Data] = []
    var fails = false

    var bodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return _bodies
    }

    /// Each `json` body as its events.
    var batches: [[[String: Any]]] {
        bodies.compactMap { (try? JSONSerialization.jsonObject(with: $0)) as? [[String: Any]] }
    }

    var names: [[String]] {
        batches.map { $0.compactMap { $0["name"] as? String } }
    }

    /// The name in each body of a mapping that sends each event on its own, `{"name": …}`.
    var eachNames: [String] {
        bodies.compactMap { ((try? JSONSerialization.jsonObject(with: $0)) as? [String: Any])?["name"] as? String }
    }

    func send(_ body: Data) throws {
        lock.lock()
        _bodies.append(body)
        lock.unlock()
        if fails { throw URLError(.cannotConnectToHost) }
    }
}

final class TelemetryTests: XCTestCase {
    static let user = "11111111-1111-4111-8111-111111111111"
    static let org = "22222222-2222-4222-8222-222222222222"

    private func build(
        _ config: TelemetryConfig,
        flushInterval: TimeInterval = 60
    ) -> (Telemetry, TelemetrySink) {
        let sink = TelemetrySink()
        var config = config
        config.format = .json
        let telemetry = Telemetry(config: config, dependencies: TelemetryDependencies(
            apiBases: ["https://api.example.com"],
            identity: { TelemetryIdentity(userId: Self.user, organizationId: Self.org) },
            send: { try sink.send($0) },
            system: TelemetryOS(name: "iOS", version: "18.0.0"),
            flushInterval: flushInterval
        ))
        return (telemetry, sink)
    }

    private func config(_ edit: (inout TelemetryConfig) -> Void = { _ in }) -> TelemetryConfig {
        var config = TelemetryConfig(endpoint: "https://collector.example.com/v1/logs")
        edit(&config)
        return config
    }

    /// A mapping that sends each event in a body of its own, `{"name": …}`.
    private func eachConfig() -> TelemetryConfig {
        var config = config()
        config.format = .mapping
        config.mapping = TelemetryMapping(template: ["name": "{{name}}"], batch: .each)
        return config
    }

    func testIsOnOnlyWithAnEndpoint() {
        XCTAssertFalse(Telemetry.isEnabled(nil))
        XCTAssertFalse(Telemetry.isEnabled(TelemetryConfig(endpoint: " ")))
        XCTAssertTrue(Telemetry.isEnabled(TelemetryConfig(endpoint: "https://collector.example.com")))
    }

    func testReportsEveryKindWithThePrefixTheIdsAndTheContextBatched() async throws {
        let (telemetry, sink) = build(config {
            $0.prefix = "acme"
            $0.context = ["platform": "Acme"]
        })
        telemetry.page("/applications")
        telemetry.api(
            method: "POST",
            url: URL(string: "https://api.example.com/applications"),
            body: Data("{}".utf8),
            outcome: .success
        )
        telemetry.api(
            method: "POST",
            url: URL(string: "https://api.example.com/groups"),
            body: Data("{}".utf8),
            outcome: .failure(status: 409, responseBody: Data(#"{"code":"GRP-1004","message":"Ada"}"#.utf8))
        )
        telemetry.auth(.signIn)
        telemetry.link(URL(string: "https://docs.example.com/guides/start?ref=x#top")!)
        telemetry.track("application.template-pick", data: ["type": "spa"])
        await telemetry.flush()

        XCTAssertEqual(sink.names, [[
            "acme.application.list-view",
            "acme.application.create",
            "acme.group.create-failed",
            "acme.auth.sign-in",
            "acme.link.open",
            "acme.application.template-pick"
        ]])
        let events = try XCTUnwrap(sink.batches.first)
        guard events.count == 6 else { return XCTFail("Expected 6 events, got \(events.count)") }
        let attributes = events.map { $0["attributes"] as? [String: Any] ?? [:] }
        XCTAssertEqual(
            attributes[2]["data"] as? [String: String],
            ["error_code": "GRP-1004", "resource_type": "group", "status": "409"]
        )
        XCTAssertEqual(attributes[4]["data"] as? [String: String], ["host": "docs.example.com", "path": "/guides/{id}"])
        XCTAssertEqual(attributes[0]["user"] as? [String: String], ["id": Self.user])
        XCTAssertEqual(attributes[0]["organization"] as? [String: String], ["id": Self.org])
        XCTAssertEqual(attributes[0]["route"] as? String, "/applications")
        XCTAssertEqual(attributes[0]["os"] as? [String: String], ["name": "iOS", "version": "18.0.0"])
        XCTAssertEqual(events[0]["context"] as? [String: String], ["platform": "Acme"])
        XCTAssertEqual(events[0]["kind"] as? String, "page")
        let body = try XCTUnwrap(sink.bodies.first.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertFalse(body.contains("Ada"))
        XCTAssertFalse(body.contains("ref=x"))
    }

    func testLeavesOutExcludedAndDisabledKindsAndRenames() async {
        let (telemetry, sink) = build(config {
            $0.apiEvents = TelemetryApiEventsConfig(exclude: ["role.*", "https://api.example.com/secrets/**"])
            $0.authEvents = TelemetryKindConfig(exclude: ["session-expired"])
            $0.links = TelemetryKindConfig(names: ["https://example.com/pricing": "plan.upgrade-click"])
            $0.pages = TelemetryKindConfig(exclude: ["/settings/**"], names: ["/home": "organization.overview-view"])
        })
        telemetry.page("/settings/general/advanced")
        telemetry.page("/home")
        telemetry.api(method: "DELETE", url: URL(string: "https://api.example.com/roles/r1"), body: nil, outcome: .success)
        telemetry.api(
            method: "DELETE",
            url: URL(string: "https://api.example.com/secrets/s1?x=1"),
            body: nil,
            outcome: .success
        )
        telemetry.auth(.sessionExpired)
        telemetry.link(URL(string: "https://example.com/pricing")!)
        telemetry.link(URL(string: "mailto:someone@example.com")!)
        telemetry.link(URL(string: "myapp://inside")!)
        await telemetry.flush()
        XCTAssertEqual(sink.names, [["organization.overview-view", "plan.upgrade-click"]])

        let (off, offSink) = build(config {
            $0.pages = TelemetryKindConfig(enabled: false)
            $0.apiEvents = TelemetryApiEventsConfig(enabled: false)
            $0.authEvents = TelemetryKindConfig(enabled: false)
            $0.links = TelemetryKindConfig(enabled: false)
        })
        off.page("/home")
        off.api(method: "POST", url: URL(string: "https://api.example.com/roles"), body: nil, outcome: .success)
        off.auth(.signOut)
        off.link(URL(string: "https://example.com")!)
        await off.flush()
        XCTAssertTrue(offSink.bodies.isEmpty)
    }

    func testRenamesAnApiEventBeforeThePrefixAndKeepsTheFailedSuffix() async throws {
        let (telemetry, sink) = build(config {
            $0.prefix = "acme"
            $0.apiEvents = TelemetryApiEventsConfig(names: ["application.create": "app.register"])
        })
        let url = URL(string: "https://api.example.com/applications")
        telemetry.api(method: "POST", url: url, body: nil, outcome: .success)
        telemetry.api(method: "POST", url: url, body: nil, outcome: .failure(status: nil, responseBody: nil))
        await telemetry.flush()
        XCTAssertEqual(sink.names, [["acme.app.register", "acme.app.register-failed"]])
        let events = try XCTUnwrap(sink.batches.first)
        let failed = try XCTUnwrap(events.dropFirst().first)
        let data = (failed["attributes"] as? [String: Any])?["data"] as? [String: String]
        XCTAssertEqual(data?["status"], "network")
    }

    func testNamesAnApiEventFromConfigFirstThenFromTheApiThenByTheBuiltInRules() async {
        let (telemetry, sink) = build(config {
            $0.apiEvents = TelemetryApiEventsConfig(
                names: ["POST /import/*": "configuration.import", "role.delete": "role.remove"]
            )
        })
        func call(_ method: String, _ path: String, _ outcome: TelemetryApiOutcome) {
            telemetry.api(
                method: method,
                url: URL(string: "https://api.example.com\(path)"),
                body: method == "DELETE" ? nil : Data("{}".utf8),
                outcome: outcome
            )
        }
        call("POST", "/import/managed", .success(event: "import.run"))
        call("POST", "/applications/a1/invitations", .success(event: "application.invite"))
        call("POST", "/applications/a1/invitations", .success(event: "Not A Name"))
        call("DELETE", "/roles/r1", .success)
        call("POST", "/export", .success)
        call("GET", "/applications", .success(event: "application.list"))
        await telemetry.flush()
        let events = sink.batches.first ?? []
        XCTAssertEqual(
            events.map { [$0["name"] as? String ?? "", ($0["attributes"] as? [String: Any])?["route"] as? String ?? ""] },
            [
                ["configuration.import", "/import/{id}"],
                ["application.invite", "/applications/{id}/invitations"],
                ["invitation.create", "/applications/{id}/invitations"],
                ["role.remove", "/roles/{id}"],
                ["api.export", "/export"]
            ]
        )
    }

    func testTakesEveryApiSpecificRuleFromConfiguration() async {
        let (telemetry, sink) = build(config {
            $0.apiEvents = TelemetryApiEventsConfig(
                exclude: ["/oauth2/**", "/**/.search"],
                names: [
                    "POST /gateways/*/apply": "deployment.deploy",
                    "POST /gateways/*/apply ?origin": "deployment.promote",
                    "POST /promotions": "deployment.promote"
                ],
                parentActions: [
                    "sharing-policies": TelemetryParentAction(create: "share", update: "share-update", delete: "unshare")
                ],
                skipWhen: ["dryRun", "preview"]
            )
        })
        let api = "https://api.example.com"
        func call(_ path: String, _ body: String, _ outcome: TelemetryApiOutcome = .success) {
            telemetry.api(method: "POST", url: URL(string: api + path), body: Data(body.utf8), outcome: outcome)
        }
        call("/gateways/g1/apply", #"{"origin":"g0"}"#)
        call("/gateways/g1/apply", "{}")
        call("/gateways/g1/apply", #"{"dryRun":true}"#)
        call("/promotions", #"{"preview":true}"#)
        call("/promotions", "{}")
        call("/applications/a1/sharing-policies", "{}")
        call("/oauth2/token", "{}")
        call("/scim/v2/Users/.search", "{}")
        call("/users/search", "{}", .success(event: "none"))
        await telemetry.flush()
        let events = sink.batches.first ?? []
        XCTAssertEqual(
            events.map { [$0["name"] as? String ?? "", ($0["attributes"] as? [String: Any])?["route"] as? String ?? ""] },
            [
                ["deployment.promote", "/gateways/{id}/apply"],
                ["deployment.deploy", "/gateways/{id}/apply"],
                ["deployment.promote", "/promotions"],
                ["application.share", "/applications/{id}/sharing-policies"]
            ]
        )
    }

    func testExcludesByUrlLiteralPathMaskedPathRuleNameAndFinalNameAndStopsTheFailedForm() async {
        let (telemetry, sink) = build(config {
            $0.apiEvents = TelemetryApiEventsConfig(
                exclude: ["/roles/r1", "/secrets/{id}", "group.create", "application.invite"],
                names: ["POST /import/*": "configuration.import"]
            )
        })
        let api = "https://api.example.com"
        func call(_ method: String, _ path: String, _ outcome: TelemetryApiOutcome = .success) {
            telemetry.api(method: method, url: URL(string: api + path), body: nil, outcome: outcome)
        }
        call("DELETE", "/roles/r1")
        call("DELETE", "/Roles/R1")
        call("DELETE", "/roles/r2")
        call("DELETE", "/secrets/9f1c2d3e")
        call("POST", "/groups")
        call("POST", "/groups", .failure(status: 409, responseBody: nil))
        call("POST", "/applications/a1/invitations", .success(event: "application.invite"))
        call("POST", "/applications/a1/invitations", .failure(status: 500, responseBody: nil, event: "application.invite"))
        call("POST", "/import/managed")
        await telemetry.flush()
        XCTAssertEqual(sink.names, [["role.delete", "configuration.import"]])
    }

    func testPrefersAConfiguredRenameOfTheRulesNameOverTheApisHeader() async {
        let (telemetry, sink) = build(config {
            $0.apiEvents = TelemetryApiEventsConfig(names: [
                "invitation.create": "application.invite-send",
                "role.revoke": "role.withdraw"
            ])
        })
        let api = "https://api.example.com"
        telemetry.api(
            method: "POST",
            url: URL(string: "\(api)/applications/a1/invitations"),
            body: nil,
            outcome: .success(event: "application.invite")
        )
        telemetry.api(
            method: "DELETE",
            url: URL(string: "\(api)/roles/r1"),
            body: nil,
            outcome: .success(event: "role.revoke")
        )
        telemetry.api(method: "DELETE", url: URL(string: "\(api)/groups/g1"), body: nil, outcome: .success(event: "none"))
        await telemetry.flush()
        // Config beats the header; a rename keyed by the header's name still applies to it.
        XCTAssertEqual(sink.names, [["application.invite-send", "role.withdraw"]])
    }

    func testReadsTheApisNameForACallFromTheResponseHeaderInAnyCase() async throws {
        let (telemetry, sink) = build(config())
        let observer = ThunderIDClient.telemetryObserver(telemetry)
        var request = URLRequest(url: URL(string: "https://api.example.com/applications/a1/invitations")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"email":"ada@example.com"}"#.utf8)
        let ok = try XCTUnwrap(HTTPURLResponse(
            url: request.url!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: ["X-Telemetry-Event": "application.invite"]
        ))
        observer(request, .response(ok, Data(#"{"email":"ada@example.com"}"#.utf8)))
        let failed = try XCTUnwrap(HTTPURLResponse(
            url: request.url!,
            statusCode: 409,
            httpVersion: nil,
            headerFields: ["x-telemetry-event": "application.invite"]
        ))
        observer(request, .response(failed, Data(#"{"code":"APP-1009","message":"ada@example.com"}"#.utf8)))
        await telemetry.flush()
        XCTAssertEqual(sink.names, [["application.invite", "application.invite-failed"]])
        let body = try XCTUnwrap(sink.bodies.first.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertFalse(body.contains("ada@"))
        XCTAssertTrue(body.contains("APP-1009"))
    }

    func testWatchesTheConfiguredApis() async {
        let (telemetry, sink) = build(config {
            $0.apiEvents = TelemetryApiEventsConfig(apis: ["https://env.example.com/v1"])
        })
        telemetry.api(
            method: "POST",
            url: URL(string: "https://env.example.com/v1/environments/dev/apply"),
            body: nil,
            outcome: .success
        )
        telemetry.api(method: "POST", url: URL(string: "https://other.example.com/apps"), body: nil, outcome: .success)
        await telemetry.flush()
        XCTAssertEqual(sink.names, [["environment.create"]])
    }

    func testSendsAFullBatchAtOnce() async throws {
        let (telemetry, sink) = build(config())
        for idx in 0..<Telemetry.batchSize {
            telemetry.track("item.count", data: ["n": String(idx)])
        }
        try await waitUntil { !sink.bodies.isEmpty }
        XCTAssertEqual(sink.names.first?.count, Telemetry.batchSize)
    }

    func testHoldsEventsUntilConsentThenSendsThem() async {
        var allowed = false
        let (telemetry, sink) = build(config { $0.consent = { allowed } })
        telemetry.page("/home")
        await telemetry.flush()
        await telemetry.flush(background: true)
        XCTAssertTrue(sink.bodies.isEmpty)
        allowed = true
        await telemetry.flush()
        XCTAssertEqual(sink.names, [["app.home-view"]])
    }

    func testKeepsAtMostTheNewestEventsWhileWaitingForConsent() async {
        var allowed = false
        let (telemetry, sink) = build(config { $0.consent = { allowed } })
        for idx in 0..<(Telemetry.maxWaiting + 5) {
            telemetry.track("item.count", data: ["n": String(idx)])
        }
        await telemetry.flush()
        allowed = true
        await telemetry.flush()
        let events = sink.batches.flatMap { $0 }
        XCTAssertEqual(events.count, Telemetry.maxWaiting)
        let first = (events.first?["attributes"] as? [String: Any])?["data"] as? [String: String]
        XCTAssertEqual(first?["n"], "5")
    }

    func testSendsAfterTheFlushInterval() async throws {
        let (telemetry, sink) = build(config(), flushInterval: 0.05)
        telemetry.page("/home")
        try await waitUntil { !sink.bodies.isEmpty }
        XCTAssertEqual(sink.names.first?.first, "app.home-view")
    }

    func testNeverLetsAFailedSendReachTheApp() async {
        let (telemetry, sink) = build(config())
        sink.fails = true
        telemetry.page("/home")
        await telemetry.flush()
        sink.fails = false
        telemetry.page("/applications")
        await telemetry.flush()
        // The failed batch is dropped, not sent again: the failed attempt, then the new event once.
        XCTAssertEqual(sink.names, [["app.home-view"], ["application.list-view"]])
    }

    func testKeepsTheEventsWhenConsentIsWithdrawnDuringASend() async throws {
        let sink = TelemetrySink()
        let latch = TelemetryLatch()
        addTeardownBlock { latch.open() }
        let consent = TelemetryConsentFlag()
        var config = config { $0.consent = { consent.allowed } }
        config.format = .json
        let telemetry = Telemetry(config: config, dependencies: TelemetryDependencies(
            apiBases: [],
            identity: { TelemetryIdentity() },
            send: { body in
                try sink.send(body)
                if sink.bodies.count == 1 { await latch.wait() }
            },
            flushInterval: 0.05,
            sendTimeout: 30
        ))
        // The timer starts the first send, so a flush can wait for it while consent is withdrawn.
        telemetry.track("item.one")
        try await waitUntil { sink.bodies.count == 1 }
        let reads = consent.reads
        telemetry.track("item.two")
        let second = Task { await telemetry.flush() }
        // The second flush has seen consent given, and waits for the first send.
        try await waitUntil { consent.reads > reads }
        consent.allowed = false
        latch.open()
        await second.value
        XCTAssertEqual(sink.names, [["item.one"]])
        consent.allowed = true
        await telemetry.flush()
        XCTAssertEqual(sink.names, [["item.one"], ["item.two"]])
    }

    func testSendsNothingMoreFromAnAbandonedBatch() async throws {
        let sink = TelemetrySink()
        let latch = TelemetryLatch()
        addTeardownBlock { latch.open() }
        let ended = expectation(description: "The abandoned batch ended")
        let telemetry = Telemetry(config: eachConfig(), dependencies: TelemetryDependencies(
            apiBases: [],
            identity: { TelemetryIdentity() },
            send: { body in
                try sink.send(body)
                await latch.wait()
            },
            flushInterval: 60,
            sendTimeout: 0.2,
            batchEnded: { ended.fulfill() }
        ))
        telemetry.track("item.one")
        telemetry.track("item.two")
        // The first send is held, so the flush returns once the batch is abandoned after its timeout.
        await telemetry.flush()
        XCTAssertEqual(sink.eachNames, ["item.one"])
        latch.open()
        await fulfillment(of: [ended], timeout: 5)
        XCTAssertEqual(sink.eachNames, ["item.one"])
    }

    func testSendsEveryBodyOfABatchInEachModeWhileConsentHolds() async {
        let sink = TelemetrySink()
        let consent = TelemetryConsentFlag()
        var config = eachConfig()
        config.consent = { consent.allowed }
        let telemetry = Telemetry(config: config, dependencies: TelemetryDependencies(
            apiBases: [],
            identity: { TelemetryIdentity() },
            send: { try sink.send($0) },
            flushInterval: 60
        ))
        telemetry.track("item.one")
        telemetry.track("item.two")
        telemetry.track("item.three")
        await telemetry.flush()
        XCTAssertEqual(sink.eachNames, ["item.one", "item.two", "item.three"])
    }

    func testChecksConsentBeforeEachBodyInEachModeAndKeepsTheUnsentEvents() async throws {
        let sink = TelemetrySink()
        let latch = TelemetryLatch()
        addTeardownBlock { latch.open() }
        let consent = TelemetryConsentFlag()
        var config = eachConfig()
        config.consent = { consent.allowed }
        let telemetry = Telemetry(config: config, dependencies: TelemetryDependencies(
            apiBases: [],
            identity: { TelemetryIdentity() },
            send: { body in
                try sink.send(body)
                if sink.bodies.count == 1 { await latch.wait() }
            },
            flushInterval: 60,
            sendTimeout: 30
        ))
        telemetry.track("item.one")
        telemetry.track("item.two")
        telemetry.track("item.three")
        let first = Task { await telemetry.flush() }
        try await waitUntil { sink.bodies.count == 1 }
        // Withdrawn while the first body is being sent: the others are not sent, and the first is not kept.
        consent.allowed = false
        latch.open()
        await first.value
        XCTAssertEqual(sink.eachNames, ["item.one"])
        consent.allowed = true
        await telemetry.flush()
        XCTAssertEqual(sink.eachNames, ["item.one", "item.two", "item.three"])
    }

    func testKeepsTheUnsentEventsOfABatchWithinTheWaitingLimit() async throws {
        let sink = TelemetrySink()
        let latch = TelemetryLatch()
        addTeardownBlock { latch.open() }
        let consent = TelemetryConsentFlag()
        var config = eachConfig()
        config.consent = { consent.allowed }
        let telemetry = Telemetry(config: config, dependencies: TelemetryDependencies(
            apiBases: [],
            identity: { TelemetryIdentity() },
            send: { body in
                try sink.send(body)
                if sink.bodies.count == 1 { await latch.wait() }
            },
            flushInterval: 60,
            sendTimeout: 30
        ))
        telemetry.track("item.one")
        telemetry.track("item.two")
        telemetry.track("item.three")
        let first = Task { await telemetry.flush() }
        try await waitUntil { sink.bodies.count == 1 }
        consent.allowed = false
        for idx in 0..<Telemetry.maxWaiting {
            telemetry.track("item.new", data: ["n": String(idx)])
        }
        latch.open()
        await first.value
        // Records every event tracked above while consent is still withdrawn, so all of them wait.
        await telemetry.flush()
        consent.allowed = true
        await telemetry.flush()
        // The unsent events are the oldest waiting, so they are the ones dropped past the limit.
        XCTAssertEqual(sink.eachNames, ["item.one"] + Array(repeating: "item.new", count: Telemetry.maxWaiting))
    }

    func testReportsALinkPathWithItsIdsAndTokensReplaced() async {
        let (telemetry, sink) = build(config())
        telemetry.link(URL(string: "https://app.example.com/reset/eyJhbGciOi.J9abc/confirm?token=x")!)
        telemetry.link(URL(string: "https://shop.example.com/orders/12345/")!)
        telemetry.link(URL(string: "https://docs.example.com/getting_started/sign-in")!)
        telemetry.link(URL(string: "https://docs.example.com")!)
        await telemetry.flush()
        let paths = sink.batches.flatMap { $0 }.map {
            (($0["attributes"] as? [String: Any])?["data"] as? [String: String])?["path"]
        }
        XCTAssertEqual(paths, ["/reset/{id}/{id}", "/orders/{id}/", "/getting_started/{id}", "/"])
        XCTAssertEqual(TelemetryNames.templatedPath("/a//b1"), "/a//{id}")
        XCTAssertEqual(TelemetryNames.templatedPath("/" + String(repeating: "a", count: 41)), "/{id}")
        XCTAssertEqual(TelemetryNames.templatedPath("/guides/getting-started"), "/guides/{id}")
        XCTAssertEqual(TelemetryNames.templatedPath("/users/alice"), "/users/{id}")
        XCTAssertEqual(TelemetryNames.templatedPath("/a/"), "/a/")
        XCTAssertEqual(TelemetryNames.templatedPath("/12345/orders"), "/{id}/{id}")
    }

    func testDropsAnAppEventWithABadNameAndValuesThatAreNotCodes() async throws {
        let (telemetry, sink) = build(config())
        telemetry.track("Application.Create")
        telemetry.track("application")
        telemetry.track("application..create")
        telemetry.track("application.create-")
        telemetry.track("application.template-pick", data: [
            "type": "spa",
            "email": "ada@example.com",
            "query": "a?b",
            "fragment": "a#b",
            "space": "Ada Lovelace",
            "url": "https://example.com",
            "long": String(repeating: "x", count: 65),
            "max": String(repeating: "x", count: 64)
        ])
        telemetry.track("acme.v2.item-open-2")
        await telemetry.flush()
        XCTAssertEqual(sink.names, [["application.template-pick", "acme.v2.item-open-2"]])
        let event = try XCTUnwrap(sink.batches.first?.first)
        let data = (event["attributes"] as? [String: Any])?["data"] as? [String: String]
        XCTAssertEqual(data, ["type": "spa", "max": String(repeating: "x", count: 64)])
    }

    func testSendsOneBatchAtATime() async throws {
        let sink = TelemetrySink()
        let latch = TelemetryLatch()
        addTeardownBlock { latch.open() }
        let gate = TelemetryGate()
        let consent = TelemetryConsentFlag()
        var config = config { $0.consent = { consent.allowed } }
        config.format = .json
        let telemetry = Telemetry(config: config, dependencies: TelemetryDependencies(
            apiBases: [],
            identity: { TelemetryIdentity() },
            send: { body in
                try sink.send(body)
                await gate.enter(holdingOn: sink.bodies.count == 1 ? latch : nil)
            },
            flushInterval: 0.05,
            sendTimeout: 30
        ))
        // The timer starts the first send, so the second flush reaches the pipeline while it is held.
        telemetry.track("item.one")
        try await waitUntil { sink.bodies.count == 1 }
        let reads = consent.reads
        telemetry.track("item.two")
        let second = Task { await telemetry.flush() }
        try await waitUntil { consent.reads > reads }
        XCTAssertEqual(sink.bodies.count, 1)
        latch.open()
        await second.value
        XCTAssertEqual(sink.names, [["item.one"], ["item.two"]])
        XCTAssertEqual(gate.maxConcurrent, 1)
    }

    func testAbandonsASlowSendAfterItsTimeout() async throws {
        let sink = TelemetrySink()
        let latch = TelemetryLatch()
        addTeardownBlock { latch.open() }
        var config = config()
        config.format = .json
        let telemetry = Telemetry(config: config, dependencies: TelemetryDependencies(
            apiBases: [],
            identity: { TelemetryIdentity() },
            send: { body in
                try sink.send(body)
                if sink.bodies.count == 1 { await latch.wait() }
            },
            flushInterval: 60,
            sendTimeout: 0.2
        ))
        telemetry.track("item.one")
        let returned = expectation(description: "The flush returned while its send was held")
        Task {
            await telemetry.flush()
            returned.fulfill()
        }
        await fulfillment(of: [returned], timeout: 5)
        XCTAssertEqual(sink.names, [["item.one"]])
        // The next batch goes after the abandoned one, though its send is still held.
        telemetry.track("item.two")
        await telemetry.flush()
        XCTAssertEqual(sink.names, [["item.one"], ["item.two"]])
    }

    func testWritesTheEventShape() async throws {
        let (telemetry, sink) = build(config())
        telemetry.track("item.open")
        await telemetry.flush()
        let event = try XCTUnwrap(sink.batches.first?.first)
        XCTAssertEqual(Set(event.keys), ["id", "name", "kind", "timestamp", "attributes", "context"])
        let timestamp = try XCTUnwrap(event["timestamp"] as? String)
        XCTAssertNotNil(timestamp.range(
            of: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$",
            options: .regularExpression
        ))
        let attributes = try XCTUnwrap(event["attributes"] as? [String: Any])
        XCTAssertEqual(Set(attributes.keys), ["data", "user", "organization", "os"])
    }

    func testUsesTheIdentityGivenWithAnEvent() async throws {
        let (telemetry, sink) = build(config())
        telemetry.auth(.signOut, identity: TelemetryIdentity(userId: "u-before", organizationId: nil))
        await telemetry.flush()
        let event = try XCTUnwrap(sink.batches.first?.first)
        let attributes = event["attributes"] as? [String: Any]
        XCTAssertEqual(attributes?["user"] as? [String: String], ["id": "u-before"])
        XCTAssertNil(attributes?["organization"])
    }
}

/// Waits until `condition` holds, for at most `timeout` seconds.
func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail("Timed out waiting")
            throw TelemetryTestTimeout()
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

/// Thrown by ``waitUntil(timeout:_:)`` so a test stops at its deadline instead of reading what never came.
struct TelemetryTestTimeout: Error {}

/// A consent answer a test changes while the telemetry reads it from a background task. It counts the reads,
/// so a test can tell when a flush has checked it.
final class TelemetryConsentFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true
    private var _reads = 0

    var allowed: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            _reads += 1
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }

    var reads: Int {
        lock.lock()
        defer { lock.unlock() }
        return _reads
    }
}

/// Holds whoever waits on it until it is opened, once and for all.
final class TelemetryLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiting.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let released = waiting
        waiting = []
        lock.unlock()
        released.forEach { $0.resume() }
    }
}

/// Counts how many sends run at once, holding a send on a latch when given one.
final class TelemetryGate: @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0
    private var _maxConcurrent = 0

    var maxConcurrent: Int {
        lock.lock()
        defer { lock.unlock() }
        return _maxConcurrent
    }

    func enter(holdingOn latch: TelemetryLatch?) async {
        change(1)
        await latch?.wait()
        change(-1)
    }

    private func change(_ delta: Int) {
        lock.lock()
        running += delta
        _maxConcurrent = max(_maxConcurrent, running)
        lock.unlock()
    }
}
