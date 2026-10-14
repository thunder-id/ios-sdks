// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Records the requests a fetcher receives and answers each with a canned response.
private final class RecordingFetcher: @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    var status = 200
    var body = Data("{}".utf8)

    var fetcher: ThunderIDFetcher {
        { [self] request in
            requests.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (body, response)
        }
    }

    func respond(_ json: String, status: Int = 200) {
        body = Data(json.utf8)
        self.status = status
    }
}

final class ManagementAPITests: XCTestCase {
    private let baseUrl = "https://localhost:8090"

    private func makeClient(
        fetcher: ThunderIDFetcher? = nil,
        endpoints: ThunderIDEndpoints = .init()
    ) async throws -> ThunderIDClient {
        let storage = InMemoryStorageAdapter()
        try TokenStore(storage: storage).save(
            TokenResponse(accessToken: "admin-token", tokenType: "Bearer", expiresIn: 3600)
        )
        let client = ThunderIDClient()
        let config = ThunderIDConfig(
            baseUrl: baseUrl,
            clientId: "client",
            endpoints: endpoints,
            http: .init(fetcher: fetcher)
        )
        _ = try await client.initialize(config: config, storage: storage)
        return client
    }

    func testManagementRequiresInitialization() {
        XCTAssertThrowsError(try ThunderIDClient().applications) { error in
            XCTAssertEqual((error as? ThunderIDError)?.code, .sdkNotInitialized)
        }
    }

    func testListSendsQueryAndAccessToken() async throws {
        let recorder = RecordingFetcher()
        recorder.respond(#"{"totalResults":1,"count":1,"applications":[{"id":"app-1","name":"App"}]}"#)
        let client = try await makeClient(fetcher: recorder.fetcher)

        let page = try await client.applications.list(limit: 5, offset: 10)

        XCTAssertEqual(page.applications.first?.name, "App")
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "\(baseUrl)/applications?limit=5&offset=10")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-token")
    }

    func testUsersAndAgentsRequestDisplay() async throws {
        let recorder = RecordingFetcher()
        recorder.respond(#"{"id":"u-1","ouId":"ou","type":"customer","display":"Alice"}"#)
        let client = try await makeClient(fetcher: recorder.fetcher)

        let user = try await client.users.get(id: "u-1")
        recorder.respond(#"{"totalResults":0,"startIndex":1,"count":0,"agents":[]}"#)
        _ = try await client.agents.list()

        XCTAssertEqual(user.display, "Alice")
        XCTAssertEqual(recorder.requests[0].url?.absoluteString, "\(baseUrl)/users/u-1?include=display")
        XCTAssertEqual(recorder.requests[1].url?.absoluteString, "\(baseUrl)/agents?include=display")
    }

    func testCreateEncodesPayloadAndDecodesStoredResource() async throws {
        let recorder = RecordingFetcher()
        recorder.respond(#"{"id":"new","name":"My SPA","url":"https://app.example.com","createdAt":"2026-01-01"}"#)
        let client = try await makeClient(fetcher: recorder.fetcher)
        var request = ApplicationRequest(name: "My SPA")
        request.url = "https://app.example.com"

        let application = try await client.applications.create(request)

        XCTAssertEqual(application.id, "new")
        XCTAssertEqual(application.name, "My SPA")
        XCTAssertEqual(application.url, "https://app.example.com")
        let sent = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(sent.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["name"] as? String, "My SPA")
        XCTAssertNil(body["description"])
    }

    func testUpdateAndDeleteTargetTheResource() async throws {
        let recorder = RecordingFetcher()
        recorder.respond(#"{"id":"ag-1","ouId":"ou","type":"default","name":"Renamed"}"#)
        let client = try await makeClient(fetcher: recorder.fetcher)
        var update = UpdateAgentRequest()
        update.name = "Renamed"

        _ = try await client.agents.update(id: "ag-1", update)
        recorder.respond("", status: 204)
        try await client.agents.delete(id: "ag-1")

        XCTAssertEqual(recorder.requests.map(\.httpMethod), ["PUT", "DELETE"])
        XCTAssertEqual(recorder.requests.map { $0.url?.absoluteString }, [
            "\(baseUrl)/agents/ag-1",
            "\(baseUrl)/agents/ag-1"
        ])
    }

    func testEndpointsOverrideTargetsTheResourceServer() async throws {
        let recorder = RecordingFetcher()
        recorder.respond("", status: 204)
        let client = try await makeClient(
            fetcher: recorder.fetcher,
            endpoints: .init(users: "https://rs.example.com/users/")
        )

        try await client.users.delete(id: "u 1")

        XCTAssertEqual(recorder.requests.first?.url?.absoluteString, "https://rs.example.com/users/u%201")
    }

    func testPerCallFetcherTakesPrecedence() async throws {
        let clientFetcher = RecordingFetcher()
        let callFetcher = RecordingFetcher()
        callFetcher.respond("", status: 204)
        let client = try await makeClient(fetcher: clientFetcher.fetcher)

        try await client.applications.delete(id: "app-1", fetcher: callFetcher.fetcher)

        XCTAssertEqual(callFetcher.requests.count, 1)
        XCTAssertTrue(clientFetcher.requests.isEmpty)
    }

    func testForbiddenAndNotFoundHaveDistinctCodes() async throws {
        let recorder = RecordingFetcher()
        let client = try await makeClient(fetcher: recorder.fetcher)

        for (status, code) in [(403, ThunderIDErrorCode.forbidden), (404, .notFound)] {
            recorder.respond("{}", status: status)
            do {
                _ = try await client.users.get(id: "u-1")
                XCTFail("Expected \(code)")
            } catch let error as ThunderIDError {
                XCTAssertEqual(error.code, code)
            }
        }
    }

    func testEmptyIdentifierFailsBeforeAnyRequest() async throws {
        let recorder = RecordingFetcher()
        let client = try await makeClient(fetcher: recorder.fetcher)

        do {
            _ = try await client.applications.get(id: " ")
            XCTFail("Expected invalidInput")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .invalidInput)
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testFlowsListSendsTheFlowTypeAndPaging() async throws {
        let recorder = RecordingFetcher()
        recorder.respond("""
        {"totalResults":75,"startIndex":31,"count":1,"flows":[
        {"id":"flow-1","handle":"password","name":"Password login","flowType":"AUTHENTICATION",
        "activeVersion":2,"isReadOnly":false,"createdAt":"2026-01-01","updatedAt":"2026-01-02"}]}
        """)
        let client = try await makeClient(fetcher: recorder.fetcher)

        let page = try await client.flows.list(limit: 30, offset: 30, flowType: .authentication)

        XCTAssertEqual(page.totalResults, 75)
        XCTAssertEqual(page.flows.first?.id, "flow-1")
        XCTAssertEqual(page.flows.first?.name, "Password login")
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "\(baseUrl)/flows?flowType=AUTHENTICATION&limit=30&offset=30")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-token")
    }

    func testFlowsListWithoutAFlowTypeSendsNoFilterAndToleratesMissingOptionalFields() async throws {
        let recorder = RecordingFetcher()
        recorder.respond(#"{"totalResults":1,"startIndex":1,"count":1,"flows":[{"id":"f","handle":"h","name":"N","flowType":"REGISTRATION"}]}"#)
        let client = try await makeClient(fetcher: recorder.fetcher)

        let page = try await client.flows.list()

        XCTAssertNil(page.flows.first?.activeVersion)
        XCTAssertEqual(recorder.requests.first?.url?.absoluteString, "\(baseUrl)/flows")
    }

    func testUserTypesListSendsPagingAndDecodesHandles() async throws {
        let recorder = RecordingFetcher()
        recorder.respond("""
        {"totalResults":2,"startIndex":1,"count":2,"types":[
        {"id":"type-1","handle":"employee","displayName":"Staff","ouId":"ou-1","allowSelfRegistration":false,"isReadOnly":false},
        {"id":"type-2","handle":"contractor","displayName":"Staff"}]}
        """)
        let client = try await makeClient(fetcher: recorder.fetcher)

        let page = try await client.userTypes.list(limit: 30, offset: 0)

        XCTAssertEqual(page.types.map(\.handle), ["employee", "contractor"])
        XCTAssertEqual(recorder.requests.first?.url?.absoluteString, "\(baseUrl)/user-types?limit=30&offset=0")
    }

    func testFlowAndUserTypeEndpointsOverrideTargetTheResourceServer() async throws {
        let recorder = RecordingFetcher()
        recorder.respond(#"{"totalResults":0,"startIndex":1,"count":0,"flows":[],"types":[]}"#)
        let client = try await makeClient(
            fetcher: recorder.fetcher,
            endpoints: .init(flows: "https://rs.example.com/flows/", userTypes: "https://rs.example.com/user-types")
        )

        _ = try await client.flows.list(flowType: .authentication)
        _ = try await client.userTypes.list(limit: 10)

        XCTAssertEqual(recorder.requests.map { $0.url?.absoluteString }, [
            "https://rs.example.com/flows?flowType=AUTHENTICATION",
            "https://rs.example.com/user-types?limit=10"
        ])
    }

    func testFlowAndUserTypeListsRequireInitialization() {
        XCTAssertThrowsError(try ThunderIDClient().flows) { error in
            XCTAssertEqual((error as? ThunderIDError)?.code, .sdkNotInitialized)
        }
        XCTAssertThrowsError(try ThunderIDClient().userTypes) { error in
            XCTAssertEqual((error as? ThunderIDError)?.code, .sdkNotInitialized)
        }
    }

    func testForbiddenOnTheFlowAndUserTypeListsHasItsOwnCode() async throws {
        let recorder = RecordingFetcher()
        recorder.respond("{}", status: 403)
        let client = try await makeClient(fetcher: recorder.fetcher)

        do {
            _ = try await client.flows.list()
            XCTFail("Expected forbidden")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .forbidden)
        }
        do {
            _ = try await client.userTypes.list()
            XCTFail("Expected forbidden")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .forbidden)
        }
    }
}
