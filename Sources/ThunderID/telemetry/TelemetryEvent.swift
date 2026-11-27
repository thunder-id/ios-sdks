// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The kinds of event reported.
enum TelemetryEventKind: String {
    case page
    case api
    case auth
    case link
    case custom
}

/// The ids an event is attributed to.
struct TelemetryIdentity: Equatable {
    var userId: String?
    var organizationId: String?
}

/// The operating system an event comes from.
struct TelemetryOS: Equatable {
    let name: String
    let version: String

    /// The running system.
    static var current: TelemetryOS {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let text = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #if os(iOS)
        return TelemetryOS(name: "iOS", version: text)
        #elseif os(tvOS)
        return TelemetryOS(name: "tvOS", version: text)
        #else
        return TelemetryOS(name: "macOS", version: text)
        #endif
    }
}

/// One reported event, before it is encoded.
struct TelemetryEvent {
    /// The full name, with the prefix: `[prefix.]<type>.<action>`.
    let name: String
    /// A unique id for the event.
    let id: String
    let kind: TelemetryEventKind
    /// When it happened, as an ISO 8601 string.
    let timestamp: String
    /// The route pattern of a screen, or the path template of an API call, never the URL itself.
    var route: String?
    var identity = TelemetryIdentity()
    var system: TelemetryOS?
    /// Codes about the event: a resource type, an HTTP status, an error code, a link's host.
    var data: [String: String] = [:]
    /// The configured context codes.
    var context: [String: String] = [:]

    /// The event as JSON values, the shape the `json` format sends and a mapping reads.
    var json: [String: Any] {
        var attributes: [String: Any] = ["data": data]
        if let route { attributes["route"] = route }
        if let id = identity.userId { attributes["user"] = ["id": id] }
        if let id = identity.organizationId { attributes["organization"] = ["id": id] }
        if let system { attributes["os"] = ["name": system.name, "version": system.version] }
        return [
            "attributes": attributes,
            "context": context,
            "id": id,
            "kind": kind.rawValue,
            "name": name,
            "timestamp": timestamp
        ]
    }

    /// An ISO 8601 time with milliseconds, in UTC.
    static func timestamp(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    /// Milliseconds since the epoch of an ISO 8601 time, or `nil`.
    static func milliseconds(_ text: String) -> Int64? {
        guard let date = isoFormatter.date(from: text) ?? plainIsoFormatter.date(from: text) else { return nil }
        return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainIsoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
