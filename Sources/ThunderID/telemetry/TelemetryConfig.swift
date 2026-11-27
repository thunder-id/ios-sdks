// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Telemetry: what people do in the app, reported to an endpoint the app configures. Off until `endpoint`
/// is set. Only codes are sent: route patterns, path templates, ids and error codes; never a URL with its
/// query, a name or anything a user typed.
///
/// ```swift
/// ThunderIDConfig(
///     baseUrl: "https://id.example.com",
///     clientId: "app",
///     telemetry: TelemetryConfig(endpoint: "https://collector.example.com/v1/logs", prefix: "acme")
/// )
/// ```
public struct TelemetryConfig {
    /// Where events are sent: a full `https` URL. Empty: telemetry is off. Any other scheme is refused, and
    /// telemetry stays off.
    public var endpoint: String
    /// The encoding. Defaults to ``TelemetryFormat/otlp``.
    public var format: TelemetryFormat
    /// The mapping, for the ``TelemetryFormat/mapping`` format.
    public var mapping: TelemetryMapping?
    /// A product prefix added to every name, such as `acme` for `acme.application.create`.
    public var prefix: String?
    /// Codes added to every event, such as the product, the plan tier or the region. `service.name` names
    /// the service in the OTLP resource, which defaults to `unknown_service`.
    public var context: [String: String]
    /// When set, nothing is sent until it returns `true`. Events wait in memory until then, at most 200 of
    /// them, the oldest dropped first. It is called from a background task, not the main thread.
    public var consent: (() -> Bool)?
    /// Where the user's and organization's ids come from.
    public var identity: TelemetryIdentityConfig
    /// The token the endpoint gets. See ``TelemetryToken``.
    public var token: TelemetryToken
    /// Screen views, from ``ThunderIDClient/trackPageView(_:)`` and the `telemetryScreen` view modifier.
    public var pages: TelemetryKindConfig
    /// API events: every create, update and delete on the SDK's API (and on ``TelemetryApiEventsConfig/apis``),
    /// on success and on failure. Which calls to skip, and any name an API needs beyond the built-in rules,
    /// come from ``TelemetryApiEventsConfig``.
    public var apiEvents: TelemetryApiEventsConfig
    /// Auth events: `auth.sign-in`, `auth.sign-in-failed`, `auth.sign-out` and `auth.session-expired`.
    public var authEvents: TelemetryKindConfig
    /// Links that leave the app, reported as `link.open`.
    public var links: TelemetryKindConfig

    public init(
        endpoint: String,
        format: TelemetryFormat = .otlp,
        mapping: TelemetryMapping? = nil,
        prefix: String? = nil,
        context: [String: String] = [:],
        consent: (() -> Bool)? = nil,
        identity: TelemetryIdentityConfig = .init(),
        token: TelemetryToken = .app,
        pages: TelemetryKindConfig = .init(),
        apiEvents: TelemetryApiEventsConfig = .init(),
        authEvents: TelemetryKindConfig = .init(),
        links: TelemetryKindConfig = .init()
    ) {
        self.endpoint = endpoint
        self.format = format
        self.mapping = mapping
        self.prefix = prefix
        self.context = context
        self.consent = consent
        self.identity = identity
        self.token = token
        self.pages = pages
        self.apiEvents = apiEvents
        self.authEvents = authEvents
        self.links = links
    }
}

/// How the events are encoded for the endpoint.
public enum TelemetryFormat: String {
    /// OpenTelemetry log records over OTLP/HTTP with JSON encoding, for an OpenTelemetry Collector.
    case otlp
    /// The events as they are, in an array.
    case json
    /// Each event reshaped by ``TelemetryConfig/mapping``, for any other API.
    case mapping
}

/// A mapping that reshapes each event for an API that does not take OpenTelemetry.
public struct TelemetryMapping {
    /// How a batch is sent.
    public enum Batch: String {
        /// Every event of the batch in one array.
        case array
        /// One request per event.
        case each
    }

    /// The shape of one event, as JSON values. Strings may hold `{{path}}` expressions read from the event,
    /// with filters (`{{attributes.user.id | uuid}}`): `uuid`, `lookup: <table>` and `date`. A key
    /// starting with `...` spreads an object value into its parent. An expression that reads nothing
    /// leaves its key out.
    public var template: [String: Any]
    /// Lookup tables, for the `lookup` filter: `{{name | lookup: features}}` reads `tables["features"][name]`.
    public var tables: [String: [String: Any]]
    /// How a batch is sent. Defaults to ``Batch/array``.
    public var batch: Batch

    public init(template: [String: Any], tables: [String: [String: Any]] = [:], batch: Batch = .array) {
        self.template = template
        self.tables = tables
        self.batch = batch
    }
}

/// Where the user's and organization's ids are read from: claim names of the ID token.
public struct TelemetryIdentityConfig {
    /// The claim holding the user's id. Defaults to `sub`.
    public var userClaim: String
    /// The claim holding the organization's id. Defaults to `ouId`.
    public var organizationClaim: String

    public init(userClaim: String = "sub", organizationClaim: String = "ouId") {
        self.userClaim = userClaim
        self.organizationClaim = organizationClaim
    }
}

/// The token the telemetry endpoint gets.
public enum TelemetryToken {
    /// The app's own access token, only for an endpoint that shares the origin of `baseUrl`, and never when
    /// sign-in runs on a backend. Any other endpoint gets no token.
    case app
    /// No token.
    case disabled
    /// This token, and never the app's own.
    case fixed(String)
}

/// The settings every automatic kind shares.
public struct TelemetryKindConfig {
    /// Whether this kind is reported. Defaults to `true`.
    public var enabled: Bool
    /// What is never reported: route patterns for screens, URLs for API events and links, and event names
    /// without the prefix (such as `session-expired`) for auth events. `*` matches the rest of one path
    /// segment and `**` the rest of the value.
    public var exclude: [String]
    /// Renames, from a route pattern, a URL or an automatic name to the name to report instead. The product
    /// prefix is still added.
    public var names: [String: String]

    public init(enabled: Bool = true, exclude: [String] = [], names: [String: String] = [:]) {
        self.enabled = enabled
        self.exclude = exclude
        self.names = names
    }
}

/// API events: what the app's own calls change.
public struct TelemetryApiEventsConfig {
    /// Whether API events are reported. Defaults to `true`.
    public var enabled: Bool
    /// What is never reported, matched against the URL without its query, the path below the API as called
    /// (lower case, such as `/roles/r1`), the path with values replaced (such as `/oauth2/**`), the rules'
    /// name and the final name. Excluding a name, such as `group.create`, also stops its `-failed` form. See
    /// ``TelemetryKindConfig/exclude`` for the patterns.
    public var exclude: [String]
    /// Renames API events. A key is either an automatic name, such as `group.create` or `api.call`, or a
    /// method and a path, such as `POST /import`, where `*` matches one segment and `**` the rest, which names
    /// any call that matches, including one the built-in rules do not name. A path key may end with `?<field>`
    /// to match only when the request body sets that field, such as `POST /promotions ?origin`. The body is
    /// read for that alone and never sent. These come first, before a name the API gives in its
    /// `X-Telemetry-Event` response header and before the built-in rules.
    public var names: [String: String]
    /// More APIs to watch with the same built-in rules as the SDK's own API: base URLs whose creates, updates
    /// and deletes are reported.
    public var apis: [String]
    /// Sub-collections reported as an action on their parent, by change:
    /// `["sharing-policies": TelemetryParentAction(create: "share", update: "share-update", delete: "unshare")]`
    /// reports `POST /applications/{id}/sharing-policies` as `application.share`.
    public var parentActions: [String: TelemetryParentAction]
    /// Request body fields that mean a call changes nothing, such as `dryRun` or `preview`: a call whose body
    /// sets one is not reported.
    public var skipWhen: [String]
    /// Top-level collections whose next path word is a kind, such as `connections`: `POST /connections/google`
    /// is then `connection.create` with `kind: google` and route `/connections/google`. Under any other
    /// collection that word is an item value, `{id}`, and never part of a name or the data. Defaults to none.
    public var kinds: [String]
    /// Words that, right after a collection, start an address, such as `tree`: with it,
    /// `PUT /organization-units/tree/engineering/operations` is `organization-unit.update` with route
    /// `/organization-units/tree/{path}`, and no word of the address is ever part of a name or the data.
    /// Defaults to none.
    public var addressWords: [String]
    /// Words that, ending a POST to a sub-collection, are an action on the parent besides the change words
    /// (`add`, `create`, `delete`, `remove`, `update`), such as `suspend`: `POST /users/{id}/agents/suspend` is
    /// then `user.agent-suspend`. Any other word there is an id the caller chose:
    /// `POST /groups/{id}/members/alice` is `member.create`. Defaults to none.
    public var actions: [String]

    public init(
        enabled: Bool = true,
        exclude: [String] = [],
        names: [String: String] = [:],
        apis: [String] = [],
        parentActions: [String: TelemetryParentAction] = [:],
        skipWhen: [String] = [],
        kinds: [String] = [],
        addressWords: [String] = [],
        actions: [String] = []
    ) {
        self.enabled = enabled
        self.exclude = exclude
        self.names = names
        self.apis = apis
        self.parentActions = parentActions
        self.skipWhen = skipWhen
        self.kinds = kinds
        self.addressWords = addressWords
        self.actions = actions
    }
}

/// The names of the actions on a parent that a sub-collection's changes are reported as.
public struct TelemetryParentAction {
    /// The action a create is reported as, such as `share`.
    public var create: String?
    /// The action an update is reported as, such as `share-update`.
    public var update: String?
    /// The action a delete is reported as, such as `unshare`.
    public var delete: String?

    public init(create: String? = nil, update: String? = nil, delete: String? = nil) {
        self.create = create
        self.update = update
        self.delete = delete
    }

    var byChange: [TelemetryChange: String] {
        var actions: [TelemetryChange: String] = [:]
        actions[.create] = create
        actions[.update] = update
        actions[.delete] = delete
        return actions
    }
}
