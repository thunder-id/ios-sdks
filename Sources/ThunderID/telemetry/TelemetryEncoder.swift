// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A request body and the events it carries.
struct TelemetryBody {
    let data: Data
    let events: [TelemetryEvent]
}

/// Encodes a batch of events into request bodies for the configured format.
struct TelemetryEncoder {
    let format: TelemetryFormat
    var mapping: TelemetryMapping?

    /// The request bodies for a batch: one, or one per event for a mapping that sends each on its own.
    func encode(_ events: [TelemetryEvent]) -> [Data] {
        encodeBodies(events).map(\.data)
    }

    /// The bodies to send for `events`, each with the events it carries: one body for them all, or one for
    /// each in `each` mode. An event that cannot be encoded is left out.
    func encodeBodies(_ events: [TelemetryEvent]) -> [TelemetryBody] {
        guard !events.isEmpty else { return [] }
        if format == .mapping, mapping?.batch == .each {
            return events.compactMap { event in
                Self.serialize(map(event)).map { TelemetryBody(data: $0, events: [event]) }
            }
        }
        return encodeAll(events).map { [TelemetryBody(data: $0, events: events)] } ?? []
    }

    /// One body for all of `events`.
    private func encodeAll(_ events: [TelemetryEvent]) -> Data? {
        switch format {
        case .json:
            return Self.serialize(events.map(\.json))
        case .mapping:
            return Self.serialize(events.map(map))
        case .otlp:
            return Self.serialize(Self.otlp(events))
        }
    }

    /// One event reshaped by the mapping's template.
    func map(_ event: TelemetryEvent) -> Any {
        let template = TelemetryTemplate(tables: mapping?.tables ?? [:])
        return template.render(mapping?.template ?? [:], event: event.json) ?? [String: Any]()
    }

    /// JSON text, with sorted keys so a body is the same for the same events.
    static func serialize(_ value: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject(value) else { return nil }
        return try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// OpenTelemetry log records (OTLP/HTTP JSON): one record per event, named by `event.name`, with the
    /// event's codes as attributes and the context as resource attributes.
    static func otlp(_ events: [TelemetryEvent]) -> [String: Any] {
        var resource: [(String, String?)] = [("service.name", "unknown_service")]
        for (key, value) in (events.first?.context ?? [:]).sorted(by: { $0.key < $1.key }) {
            resource.removeAll { $0.0 == key }
            resource.append((key, value))
        }
        let records: [[String: Any]] = events.map { event in
            var values: [(String, String?)] = [
                ("event.id", event.id),
                ("event.kind", event.kind.rawValue),
                ("event.name", event.name),
                ("organization.id", event.identity.organizationId),
                ("url.template", event.route),
                ("user.id", event.identity.userId),
                ("os.name", event.system?.name),
                ("os.version", event.system?.version)
            ]
            values += event.data.sorted { $0.key < $1.key }.map { ("event.data.\($0.key)", $0.value) }
            let millis = TelemetryEvent.milliseconds(event.timestamp) ?? 0
            return [
                "attributes": attributes(values),
                "body": ["stringValue": event.name],
                "eventName": event.name,
                "timeUnixNano": "\(millis)000000"
            ]
        }
        let scopeLogs: [String: Any] = ["logRecords": records, "scope": ["name": "telemetry"]]
        let resourceLogs: [String: Any] = [
            "resource": ["attributes": attributes(resource)],
            "scopeLogs": [scopeLogs]
        ]
        return ["resourceLogs": [resourceLogs]]
    }

    private static func attributes(_ values: [(String, String?)]) -> [[String: Any]] {
        values.compactMap { key, value in
            value.map { ["key": key, "value": ["stringValue": $0]] }
        }
    }
}

/// Renders a mapping template against one event.
struct TelemetryTemplate {
    private static let uuid = try? NSRegularExpression(
        pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\z",
        options: [.caseInsensitive]
    )
    private static let expression = try? NSRegularExpression(pattern: "\\{\\{([^}]+)\\}\\}")

    let tables: [String: [String: Any]]

    /// Renders a template node: strings with expressions are filled in, objects and arrays recursively, a
    /// `...` key spreads its object value, and a key whose value reads nothing is left out.
    func render(_ node: Any, event: [String: Any]) -> Any? {
        switch node {
        case let text as String:
            return fill(text, event: event)
        case let array as [Any]:
            return array.compactMap { render($0, event: event) }
        case let object as [String: Any]:
            var result: [String: Any] = [:]
            // Spreads in key order, so the result does not depend on the dictionary's order.
            for (key, value) in object.sorted(by: { $0.key < $1.key }) {
                let rendered = render(value, event: event)
                if key.hasPrefix("...") {
                    if let spread = rendered as? [String: Any] {
                        result.merge(spread) { _, new in new }
                    }
                } else if let rendered {
                    result[key] = rendered
                }
            }
            return result
        default:
            return node
        }
    }

    /// A template string with its expressions filled in. A string that is a single expression keeps the
    /// value's type; a string any of whose expressions reads nothing is nothing.
    private func fill(_ template: String, event: [String: Any]) -> Any? {
        guard let regex = Self.expression else { return template }
        let full = NSRange(template.startIndex..., in: template)
        let matches = regex.matches(in: template, range: full)
        if matches.count == 1, matches[0].range == full, let inner = Range(matches[0].range(at: 1), in: template) {
            return evaluate(String(template[inner]), event: event)
        }
        var filled = ""
        var cursor = template.startIndex
        for match in matches {
            guard let whole = Range(match.range, in: template),
                  let inner = Range(match.range(at: 1), in: template) else { continue }
            filled += template[cursor..<whole.lowerBound]
            guard let value = evaluate(String(template[inner]), event: event), !(value is NSNull) else {
                return nil
            }
            filled += Self.text(value)
            cursor = whole.upperBound
        }
        filled += template[cursor...]
        return filled
    }

    private static func text(_ value: Any) -> String {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        if let data = TelemetryEncoder.serialize(value) { return String(data: data, encoding: .utf8) ?? "" }
        return "\(value)"
    }

    /// An expression's value: a dotted path into the event, through its filters.
    private func evaluate(_ expression: String, event: [String: Any]) -> Any? {
        let parts = expression.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var value: Any? = event
        for key in parts[0].split(separator: ".", omittingEmptySubsequences: false) {
            value = (value as? [String: Any])?[String(key)]
        }
        for filter in parts.dropFirst() {
            value = apply(filter, to: value)
        }
        return value
    }

    /// One filter:
    ///
    /// - `uuid`: the value when it is a UUID, lower-cased, else nothing;
    /// - `lookup: <table>`: the value's entry in one of the mapping's tables;
    /// - `date`: an ISO 8601 time as milliseconds since the epoch.
    private func apply(_ filter: String, to value: Any?) -> Any? {
        let parts = filter.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        switch parts.first ?? "" {
        case "uuid":
            guard let text = value as? String, let regex = Self.uuid,
                  regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else {
                return nil
            }
            return text.lowercased()
        case "lookup":
            guard let text = value as? String, parts.count > 1 else { return nil }
            return tables[parts[1]]?[text]
        case "date":
            guard let text = value as? String else { return nil }
            return TelemetryEvent.milliseconds(text)
        default:
            return value
        }
    }
}
