// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Replays the API naming vectors shared by every SDK: each call must give the same event, or none.
final class TelemetryApiVectorsTests: XCTestCase {
    private struct Vectors: Decodable {
        let apiBase: String
        let configs: [String: Config]
        let cases: [Case]
    }

    private struct Config: Decodable {
        var exclude: [String]?
        var names: [String: String]?
        var parentActions: [String: [String: String]]?
        var skipWhen: [String]?
        var kinds: [String]?
        var addressWords: [String]?
        var actions: [String]?
    }

    private struct Case: Decodable {
        let config: String
        let method: String
        let path: String
        let body: JSONValue?
        let outcome: Outcome
        let expect: Expected?
    }

    private struct Outcome: Decodable {
        let ok: Bool
        let status: Int?
        let responseBody: JSONValue?
    }

    private struct Expected: Decodable, Equatable {
        let name: String
        let route: String
        let data: [String: String]
    }

    /// A JSON value kept as it is, to send as a request or response body.
    private struct JSONValue: Decodable {
        let data: Data

        init(from decoder: Decoder) throws {
            data = try JSONEncoder().encode(try decoder.singleValueContainer().decode(AnyCodable.self))
        }
    }

    private func loadVectors() throws -> Vectors {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/telemetry-api-vectors.json")
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }

    private func apiEvents(_ config: Config) -> TelemetryApiEventsConfig {
        TelemetryApiEventsConfig(
            exclude: config.exclude ?? [],
            names: config.names ?? [:],
            parentActions: (config.parentActions ?? [:]).mapValues {
                TelemetryParentAction(create: $0["create"], update: $0["update"], delete: $0["delete"])
            },
            skipWhen: config.skipWhen ?? [],
            kinds: config.kinds ?? [],
            addressWords: config.addressWords ?? [],
            actions: config.actions ?? []
        )
    }

    /// Every event a case reports, across every batch sent.
    private func replay(_ vector: Case, base: String, config: Config) async -> [Expected] {
        let sink = TelemetrySink()
        var telemetryConfig = TelemetryConfig(endpoint: "https://collector.example.com/v1/logs", format: .json)
        telemetryConfig.apiEvents = apiEvents(config)
        let telemetry = Telemetry(config: telemetryConfig, dependencies: TelemetryDependencies(
            apiBases: [base],
            identity: { TelemetryIdentity() },
            send: { try sink.send($0) },
            flushInterval: 60
        ))
        let outcome: TelemetryApiOutcome = vector.outcome.ok
            ? .success
            : .failure(status: vector.outcome.status, responseBody: vector.outcome.responseBody?.data)
        telemetry.api(
            method: vector.method,
            url: URL(string: base + vector.path),
            body: vector.body?.data,
            outcome: outcome
        )
        await telemetry.flush()
        return sink.batches.flatMap { $0 }.map { event in
            let attributes = event["attributes"] as? [String: Any]
            return Expected(
                name: event["name"] as? String ?? "",
                route: attributes?["route"] as? String ?? "",
                data: attributes?["data"] as? [String: String] ?? [:]
            )
        }
    }

    func testReplaysTheSharedApiNamingVectors() async throws {
        let vectors = try loadVectors()
        XCTAssertEqual(vectors.cases.count, 552)
        var failures = 0
        for vector in vectors.cases {
            guard let config = vectors.configs[vector.config] else {
                XCTFail("Unknown config \(vector.config)")
                continue
            }
            let actual = await replay(vector, base: vectors.apiBase, config: config)
            // The whole result is compared, so a call that reports its event twice fails too.
            let expected = vector.expect.map { [$0] } ?? []
            if actual != expected {
                failures += 1
                XCTFail("[\(vector.config)] \(vector.method) \(vector.path): got \(actual), "
                    + "expected \(expected)")
            }
        }
        XCTAssertEqual(failures, 0)
    }
}
