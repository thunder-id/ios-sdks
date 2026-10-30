// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class BackendEndpointsTests: XCTestCase {
    private let backendBase = "https://app.example.com"

    func testEndpointsDefaultUnderApiAuthResolvedAgainstBaseUrl() throws {
        let resolved = try ResolvedBackendEndpoints.resolve(.init(), baseUrl: "\(backendBase)/")

        XCTAssertEqual(resolved.baseUrl, backendBase)
        XCTAssertEqual(resolved.signIn.absoluteString, "\(backendBase)/api/auth/signin")
        XCTAssertEqual(resolved.session.absoluteString, "\(backendBase)/api/auth/session")
        XCTAssertEqual(resolved.checkSession.absoluteString, "\(backendBase)/api/auth/checksession")
        XCTAssertEqual(resolved.refresh.absoluteString, "\(backendBase)/api/auth/refresh")
        XCTAssertEqual(resolved.signOut.absoluteString, "\(backendBase)/api/auth/signout")
        XCTAssertEqual(resolved.proxy, "\(backendBase)/api/auth/proxy")
        XCTAssertEqual(resolved.token.absoluteString, "\(backendBase)/api/auth/token")
        XCTAssertEqual(resolved.bypassUrls, [])
        XCTAssertTrue(resolved.attachToken)
    }

    func testRelativeOverridesResolveAgainstBaseUrl() throws {
        let resolved = try ResolvedBackendEndpoints.resolve(
            .init(
                signIn: "/auth/login",
                proxy: "/auth/api/",
                token: "/auth/dp-token",
                bypass: .init(urls: ["https://dp.example.com/api/"], attachToken: false)
            ),
            baseUrl: "\(backendBase)/bff"
        )

        XCTAssertEqual(resolved.signIn.absoluteString, "\(backendBase)/bff/auth/login")
        XCTAssertEqual(resolved.session.absoluteString, "\(backendBase)/bff/api/auth/session")
        XCTAssertEqual(resolved.proxy, "\(backendBase)/bff/auth/api")
        XCTAssertEqual(resolved.token.absoluteString, "\(backendBase)/bff/auth/dp-token")
        XCTAssertEqual(resolved.bypassUrls, ["https://dp.example.com/api"])
        XCTAssertFalse(resolved.attachToken)
    }

    func testAbsoluteHTTPSEndpointsAreUsedAsIs() throws {
        let resolved = try ResolvedBackendEndpoints.resolve(
            .init(session: "https://auth.example.com/session", proxy: "https://gateway.example.com/proxy/"),
            baseUrl: backendBase
        )

        XCTAssertEqual(resolved.session.absoluteString, "https://auth.example.com/session")
        XCTAssertEqual(resolved.proxy, "https://gateway.example.com/proxy")
        XCTAssertEqual(resolved.signIn.absoluteString, "\(backendBase)/api/auth/signin")
    }

    func testRejectsABaseUrlThatIsNotHTTPS() {
        for baseUrl in ["http://app.example.com", "app.example.com", ""] {
            XCTAssertThrowsError(try ResolvedBackendEndpoints.resolve(.init(), baseUrl: baseUrl)) {
                XCTAssertEqual(($0 as? ThunderIDError)?.code, .invalidConfiguration, baseUrl)
            }
        }
    }

    func testRejectsAnEndpointThatIsNeitherAPathNorAnHTTPSUrl() {
        for value in ["http://app.example.com/session", "//evil.example.com/session", "api/auth/session"] {
            XCTAssertThrowsError(try ResolvedBackendEndpoints.resolve(.init(session: value), baseUrl: backendBase)) {
                XCTAssertEqual(($0 as? ThunderIDError)?.code, .invalidConfiguration, value)
            }
        }
    }

    func testRejectsABypassUrlThatIsNotHTTPS() {
        XCTAssertThrowsError(
            try ResolvedBackendEndpoints.resolve(.init(bypass: .init(urls: ["http://dp.example.com"])), baseUrl: backendBase)
        )
    }

    func testSendsAUrlAlreadyUnderTheProxyAsItIs() throws {
        let resolved = try ResolvedBackendEndpoints.resolve(.init(), baseUrl: backendBase)
        let proxy = "\(backendBase)/api/auth/proxy"

        XCTAssertEqual(resolved.proxyURL(for: URL(string: "\(proxy)/users/me")!)?.absoluteString, "\(proxy)/users/me")
        XCTAssertEqual(resolved.proxyURL(for: URL(string: "\(proxy)?a=1")!)?.absoluteString, "\(proxy)?a=1")
        XCTAssertEqual(resolved.proxyURL(for: URL(string: proxy)!)?.absoluteString, proxy)
    }

    func testMapsAPathToTheProxy() throws {
        let resolved = try ResolvedBackendEndpoints.resolve(.init(proxy: "/auth/api/"), baseUrl: "\(backendBase)/bff")

        XCTAssertEqual(
            resolved.proxyURL(for: URL(string: "/users/me?a=1")!)?.absoluteString,
            "\(backendBase)/bff/auth/api/users/me?a=1"
        )
    }

    func testDoesNotProxyAnyOtherAbsoluteUrl() throws {
        let resolved = try ResolvedBackendEndpoints.resolve(.init(), baseUrl: backendBase)

        XCTAssertNil(resolved.proxyURL(for: URL(string: "\(backendBase)/users/me")!))
        XCTAssertNil(resolved.proxyURL(for: URL(string: "\(backendBase)/api/auth/proxyx/users")!))
        XCTAssertNil(resolved.proxyURL(for: URL(string: "https://app.example.com.attacker.test/api/auth/proxy/users")!))
        XCTAssertNil(resolved.proxyURL(for: URL(string: "https://api.example.com/users")!))
        XCTAssertNil(resolved.proxyURL(for: URL(string: "//evil.example.com/users")!))
    }

    func testMatchesBypassUrlsAtAPathBoundary() throws {
        let resolved = try ResolvedBackendEndpoints.resolve(
            .init(bypass: .init(urls: ["https://dp.example.com/api"])),
            baseUrl: backendBase
        )

        XCTAssertTrue(resolved.isBypassed(URL(string: "https://dp.example.com/api")!))
        XCTAssertTrue(resolved.isBypassed(URL(string: "https://dp.example.com/api/orders")!))
        XCTAssertTrue(resolved.isBypassed(URL(string: "https://dp.example.com/api?page=2")!))
        XCTAssertFalse(resolved.isBypassed(URL(string: "https://dp.example.com/apiv2")!))
        XCTAssertFalse(resolved.isBypassed(URL(string: "https://dp.example.com.attacker.test/api")!))
    }

    func testInitializeRejectsABaseUrlThatIsNotHTTPSInBackendMode() async {
        let config = ThunderIDConfig(baseUrl: "http://app.example.com", endpoints: .init(backend: .init()))
        do {
            _ = try await ThunderIDClient().initialize(config: config, storage: InMemoryStorageAdapter())
            XCTFail("Expected INVALID_CONFIGURATION")
        } catch {
            XCTAssertEqual((error as? ThunderIDError)?.code, .invalidConfiguration)
        }
    }

    func testAppsWithoutABackendStayInRedirectMode() async throws {
        let client = ThunderIDClient()
        _ = try await client.initialize(
            config: ThunderIDConfig(baseUrl: "https://auth.example.com", clientId: "app"),
            storage: InMemoryStorageAdapter()
        )

        XCTAssertFalse(client.isBackendMode)
        XCTAssertFalse(client.isLoading())
        let url = try client.buildSignInURL()
        XCTAssertEqual(url.path, "/oauth2/authorize")
    }
}
