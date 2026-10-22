// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// One management collection the SDK addresses, with the `ThunderIDEndpoints` field that overrides it.
struct ManagementCollection: Identifiable {
    /// The default path under `baseUrl`, also the collection's label.
    let path: String
    /// The `Config.plist` key that overrides this collection's URL.
    let configKey: String
    let field: WritableKeyPath<ThunderIDEndpoints, String?>

    var id: String { path }

    static let all: [ManagementCollection] = [
        ManagementCollection(path: "applications", configKey: "THUNDERID_ENDPOINT_APPLICATIONS", field: \.applications),
        ManagementCollection(path: "users", configKey: "THUNDERID_ENDPOINT_USERS", field: \.users),
        ManagementCollection(path: "user-types", configKey: "THUNDERID_ENDPOINT_USER_TYPES", field: \.userTypes),
        ManagementCollection(path: "groups", configKey: "THUNDERID_ENDPOINT_GROUPS", field: \.groups),
        ManagementCollection(path: "roles", configKey: "THUNDERID_ENDPOINT_ROLES", field: \.roles),
        ManagementCollection(path: "agents", configKey: "THUNDERID_ENDPOINT_AGENTS", field: \.agents),
        ManagementCollection(path: "agent-types", configKey: "THUNDERID_ENDPOINT_AGENT_TYPES", field: \.agentTypes)
    ]
}

/// Where a collection's URL came from.
enum EndpointSource: String {
    /// A per-collection `THUNDERID_ENDPOINT_*` key.
    case override
    /// No override, so the SDK falls back to `{baseUrl}/{collection}`.
    case baseUrl = "base URL"
}

struct ResolvedEndpoint: Identifiable {
    let collection: ManagementCollection
    let url: String
    let source: EndpointSource

    var id: String { collection.id }
}

extension PlaygroundConfig {
    /// The `ThunderIDEndpoints` handed to the SDK: each `THUNDERID_ENDPOINT_*` key as given. Anything
    /// left `nil` falls back to `{baseUrl}/{collection}` inside the SDK.
    var sdkEndpoints: ThunderIDEndpoints {
        var endpoints = ThunderIDEndpoints()
        for collection in ManagementCollection.all {
            endpoints[keyPath: collection.field] = endpointOverrides[collection.path]
        }
        return endpoints
    }

    /// The URL each collection resolves to, mirroring the SDK's `endpoints[field] ?? "{baseUrl}/{collection}"`.
    /// The SDK keeps that resolution internal, so the endpoints check confirms it against the URLs
    /// the SDK actually requests.
    var resolvedEndpoints: [ResolvedEndpoint] {
        let endpoints = sdkEndpoints
        return ManagementCollection.all.map { collection in
            let source: EndpointSource = endpointOverrides[collection.path] != nil ? .override : .baseUrl
            let url = endpoints[keyPath: collection.field] ?? "\(baseUrl)/\(collection.path)"
            return ResolvedEndpoint(collection: collection, url: url, source: source)
        }
    }

    /// Whether any management collection has its own `THUNDERID_ENDPOINT_*` key.
    var hasEndpointOverrides: Bool {
        !endpointOverrides.isEmpty
    }
}
