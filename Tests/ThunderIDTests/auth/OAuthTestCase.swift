// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Sets up a client whose requests a ``StubBackend`` answers, for the OAuth and organization unit tests.
class OAuthTestCase: XCTestCase {
    let base = "https://id.example.com"
    var storage: InMemoryStorageAdapter!
    var client: ThunderIDClient!
    var sleeps: [TimeInterval] = []

    override func setUp() {
        super.setUp()
        StubBackend.reset()
        storage = InMemoryStorageAdapter()
        sleeps = []
    }

    override func tearDown() {
        StubBackend.reset()
        super.tearDown()
    }

    func makeClient(
        clientId: String? = "client-1",
        clientSecret: String? = nil,
        applicationId: String? = nil,
        pushedAuthorizationRequests: Bool = false
    ) async throws {
        let config = ThunderIDConfig(
            baseUrl: base,
            clientId: clientId,
            scopes: ["openid", "profile"],
            afterSignInUrl: "myapp://callback",
            clientSecret: clientSecret,
            pushedAuthorizationRequests: pushedAuthorizationRequests,
            applicationId: applicationId,
            tokenValidation: .init(validate: false)
        )
        client = ThunderIDClient()
        _ = try await client.initialize(config: config, storage: storage, session: StubBackend.makeSession())
        client.pollSleep = { [weak self] seconds in self?.sleeps.append(seconds) }
    }

    /// An unsigned JWT carrying `claims`, as the client decodes it.
    static func jwt(_ claims: [String: Any]) -> String {
        let encode: (Data) -> String = {
            $0.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = encode(Data(#"{"alg":"none"}"#.utf8))
        let payload = encode((try? JSONSerialization.data(withJSONObject: claims)) ?? Data())
        return "\(header).\(payload).sig"
    }

    func storeSession(_ claims: [String: Any], refreshToken: String? = nil, deviceSecret: String? = nil) throws {
        try TokenStore(storage: storage).save(TokenResponse(
            accessToken: Self.jwt(claims),
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: refreshToken,
            deviceSecret: deviceSecret
        ))
    }

    var store: TokenStore { TokenStore(storage: storage) }

    /// The form fields of a recorded URL-encoded request.
    func form(_ recorded: StubBackend.Recorded?) -> [String: String] {
        guard let body = recorded?.body, let text = String(data: body, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            let value = parts.count > 1 ? parts[1].removingPercentEncoding ?? parts[1] : ""
            result[parts[0]] = value
        }
        return result
    }

    func tokenJSON(_ claims: [String: Any], refresh: String? = nil) -> String {
        var json: [String: Any] = ["access_token": Self.jwt(claims), "token_type": "Bearer", "expires_in": 3600]
        if let refresh { json["refresh_token"] = refresh }
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func assertThrows(
        _ code: ThunderIDErrorCode,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected \(code.rawValue)", file: file, line: line)
        } catch {
            XCTAssertEqual((error as? ThunderIDError)?.code, code, "\(error)", file: file, line: line)
        }
    }
}
