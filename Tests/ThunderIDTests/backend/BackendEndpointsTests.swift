// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

final class BackendEndpointsTests: XCTestCase {
    private let apiBase = "https://api.example.com"

    func testEndpointsDefaultUnderApiAuthResolvedAgainstTheBackendBaseUrl() throws {
        let resolved = try ResolvedBackendEndpoints.resolve(
            .init(baseUrl: "https://app.example.com/"),
            apiBaseUrl: "\(apiBase)/"
        )

        XCTAssertEqual(resolved.baseUrl, "https://app.example.com")
        XCTAssertEqual(resolved.apiBaseUrl, apiBase)
        XCTAssertEqual(resolved.signIn.absoluteString, "https://app.example.com/api/auth/signin")
        XCTAssertEqual(resolved.session.absoluteString, "https://app.example.com/api/auth/session")
        XCTAssertEqual(resolved.checkSession.absoluteString, "https://app.example.com/api/auth/checksession")
        XCTAssertEqual(resolved.refresh.absoluteString, "https://app.example.com/api/auth/refresh")
        XCTAssertEqual(resolved.signOut.absoluteString, "https://app.example.com/api/auth/signout")
        XCTAssertEqual(resolved.proxy, "https://app.example.com/api/auth/proxy")
        XCTAssertEqual(resolved.token.absoluteString, "https://app.example.com/api/auth/token")
        XCTAssertEqual(resolved.bypassUrls, [])
        XCTAssertTrue(resolved.attachToken)
    }

    func testOverridesReplaceTheDefaults() throws {
        let resolved = try ResolvedBackendEndpoints.resolve(
            .init(
                baseUrl: "https://app.example.com/bff",
                signIn: "/auth/login",
                proxy: "/auth/api/",
                token: "/auth/dp-token",
                bypass: .init(urls: ["https://dp.example.com/api/"], attachToken: false)
            ),
            apiBaseUrl: apiBase
        )

        XCTAssertEqual(resolved.signIn.absoluteString, "https://app.example.com/bff/auth/login")
        XCTAssertEqual(resolved.session.absoluteString, "https://app.example.com/bff/api/auth/session")
        XCTAssertEqual(resolved.proxy, "https://app.example.com/bff/auth/api")
        XCTAssertEqual(resolved.token.absoluteString, "https://app.example.com/bff/auth/dp-token")
        XCTAssertEqual(resolved.bypassUrls, ["https://dp.example.com/api"])
        XCTAssertFalse(resolved.attachToken)
    }

    func testRejectsABackendBaseUrlThatIsNotHTTPS() {
        for baseUrl in ["http://app.example.com", "app.example.com", ""] {
            XCTAssertThrowsError(try ResolvedBackendEndpoints.resolve(.init(baseUrl: baseUrl), apiBaseUrl: apiBase)) {
                XCTAssertEqual(($0 as? ThunderIDError)?.code, .invalidConfiguration, baseUrl)
            }
        }
    }

    func testRejectsAnEndpointThatIsNotAPathUnderTheBaseUrl() {
        for path in ["https://evil.example.com/session", "//evil.example.com/session", "api/auth/session"] {
            let endpoints = ThunderIDBackendEndpoints(baseUrl: "https://app.example.com", session: path)
            XCTAssertThrowsError(try ResolvedBackendEndpoints.resolve(endpoints, apiBaseUrl: apiBase)) {
                XCTAssertEqual(($0 as? ThunderIDError)?.code, .invalidConfiguration, path)
            }
        }
    }

    func testRejectsABypassUrlThatIsNotHTTPS() {
        let endpoints = ThunderIDBackendEndpoints(
            baseUrl: "https://app.example.com",
            bypass: .init(urls: ["http://dp.example.com"])
        )
        XCTAssertThrowsError(try ResolvedBackendEndpoints.resolve(endpoints, apiBaseUrl: apiBase))
    }

    func testMapsUrlsUnderTheApiBaseToTheProxyAtAPathBoundary() throws {
        let resolved = try ResolvedBackendEndpoints.resolve(.init(baseUrl: "https://app.example.com"), apiBaseUrl: apiBase)
        let proxy = "https://app.example.com/api/auth/proxy"

        XCTAssertEqual(resolved.proxyURL(for: URL(string: "\(apiBase)/users/me")!)?.absoluteString, "\(proxy)/users/me")
        XCTAssertEqual(resolved.proxyURL(for: URL(string: "\(apiBase)?a=1")!)?.absoluteString, "\(proxy)/?a=1")
        XCTAssertEqual(resolved.proxyURL(for: URL(string: apiBase)!)?.absoluteString, "\(proxy)/")
        XCTAssertNil(resolved.proxyURL(for: URL(string: "https://api.example.com.attacker.test/users")!))
        XCTAssertNil(resolved.proxyURL(for: URL(string: "https://api.example.comx/users")!))
        XCTAssertNil(resolved.proxyURL(for: URL(string: "https://other.example.com/users")!))
    }

    func testMatchesBypassUrlsAtAPathBoundary() throws {
        let resolved = try ResolvedBackendEndpoints.resolve(
            .init(baseUrl: "https://app.example.com", bypass: .init(urls: ["https://dp.example.com/api"])),
            apiBaseUrl: apiBase
        )

        XCTAssertTrue(resolved.isBypassed(URL(string: "https://dp.example.com/api")!))
        XCTAssertTrue(resolved.isBypassed(URL(string: "https://dp.example.com/api/orders")!))
        XCTAssertTrue(resolved.isBypassed(URL(string: "https://dp.example.com/api?page=2")!))
        XCTAssertFalse(resolved.isBypassed(URL(string: "https://dp.example.com/apiv2")!))
        XCTAssertFalse(resolved.isBypassed(URL(string: "https://dp.example.com.attacker.test/api")!))
    }

    func testInitializeRejectsABackendBaseUrlThatIsNotHTTPS() async {
        let config = ThunderIDConfig(
            baseUrl: apiBase,
            endpoints: .init(backend: .init(baseUrl: "http://app.example.com"))
        )
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
            config: ThunderIDConfig(baseUrl: apiBase, clientId: "app"),
            storage: InMemoryStorageAdapter()
        )

        XCTAssertFalse(client.isBackendMode)
        XCTAssertFalse(client.isLoading())
        let url = try client.buildSignInURL()
        XCTAssertEqual(url.path, "/oauth2/authorize")
    }
}
