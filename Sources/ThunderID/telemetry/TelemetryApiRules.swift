// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A call that is reported: its name before the prefix, its path template and its codes.
struct TelemetryApiCall: Equatable {
    let name: String
    let route: String
    let data: [String: String]
}

/// Names an API call from its method and path alone, the same way for any REST API, with no knowledge of a
/// particular API:
///
/// - `POST /<collection>` is `<type>.create`; `PUT` or `PATCH /<collection>/{id}` is `<type>.update`;
///   `DELETE /<collection>/{id}` is `<type>.delete`. Words in front of the first collection, such as
///   `design` in `/design/themes`, are skipped.
/// - The word right after a top-level collection listed in `kinds`, as in `/connections/google/{id}`, is
///   reported as `kind`, whatever follows it. Under any other collection that word is an item value, `{id}`.
/// - A word listed in `addressWords` right after a collection starts an address: `/organization-units/tree/a/b`
///   is a change to `organization-unit` at `/organization-units/tree/{path}`.
/// - A sub-resource is named for itself and carries `parent_type`: `POST /resource-servers/{id}/actions` is
///   `action.create`, unless `parentActions` reports it as an action on the parent.
/// - A change word, or a word listed in `actions`, ending a POST to a sub-collection is an action on the
///   parent: `POST /groups/{id}/members/add` is `group.member-add`, with `sub_type: member`. Any other word
///   there is an id the caller chose: `POST /groups/{id}/members/alice` is `member.create`. Words after an id
///   are an action on the item: `POST /applications/{id}/client-secret/regenerate` is
///   `application.client-secret-regenerate`.
/// - Words after an item that is itself a word are part of its address and never part of a name:
///   `PUT /organization-units/tree/a/b` is `organization-unit.update` at `/organization-units/{id}/{path}`.
/// - Under a sub-collection, a word and the value after it in front of a further sub-collection are a label
///   and its value: `/languages/{id}/translations/ns/{ns}/keys` keeps `ns` and drops the value.
/// - A path of words alone is named from them: `POST /import` is `api.import`.
/// - Any other change is `api.call`, with its method and path template, so nothing is lost.
///
/// Only `POST`, `PUT`, `PATCH` and `DELETE` are named. Which calls to skip, and any name an API needs beyond
/// these rules, come from configuration.
struct TelemetryApiRules {
    /// The server's error code format, such as `APP-1023`.
    private static let errorCode = try? NSRegularExpression(pattern: "^[A-Z][A-Z0-9_]*-\\d+\\z")
    /// A plain word in a path: letters and hyphens. Anything else, such as a UUID or a name, is a value.
    private static let word = try? NSRegularExpression(pattern: "^[A-Za-z][A-Za-z-]{0,39}\\z")
    /// A path segment kept in a template: a word that may hold a version digit, such as `v2` or `oauth2`.
    private static let templateWord = try? NSRegularExpression(pattern: "^\\.?[A-Za-z][A-Za-z0-9-]{0,39}\\z")
    /// An API version in a path, such as `v2`.
    private static let version = try? NSRegularExpression(pattern: "^v\\d{1,2}\\z")

    /// The words of the naming scheme itself. A hyphenated segment that starts with one, such as
    /// `update-credentials`, is an action and not a collection, even though it ends in `s`.
    private static let changeWords: Set<String> = ["add", "create", "delete", "remove", "update"]

    /// The base URLs of the APIs that are watched.
    let bases: [String]
    /// The words of the watched APIs that the rules cannot tell from a path alone, from configuration.
    let vocabulary: TelemetryApiVocabulary

    /// - Parameters:
    ///   - parentActions: Sub-collections reported as an action on their parent, by change:
    ///     `["sharing-policies": [.create: "share"]]` reports `POST /applications/{id}/sharing-policies` as
    ///     `application.share`.
    ///   - kinds: Top-level collections whose next word is a kind, such as `connections`.
    ///   - addressWords: Words after a collection that start an address, such as `tree`.
    ///   - actions: Words that end a POST to a sub-collection as an action on the parent, such as `suspend`.
    init(
        bases: [String],
        parentActions: [String: [TelemetryChange: String]] = [:],
        kinds: [String] = [],
        addressWords: [String] = [],
        actions: [String] = []
    ) {
        self.bases = bases
        vocabulary = TelemetryApiVocabulary(
            parentActions: parentActions,
            kinds: Set(kinds.map { $0.lowercased() }),
            addressWords: Set(addressWords.map { $0.lowercased() }),
            actions: Set(actions.map { $0.lowercased() })
        )
    }

    /// Whether a request body sets `field` to a value other than `false`, `null` or an empty string. Only
    /// read here, never sent.
    static func sets(_ body: Data?, _ field: String) -> Bool {
        guard let value = parse(body)?[field], !(value is NSNull) else { return false }
        if let text = value as? String { return !text.isEmpty }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        return true
    }

    /// What a failed call is reported with: the HTTP status and the API's own error code, such as
    /// `APP-1023`, when it gave one. Never the message, which can quote what the user typed.
    static func failureData(status: Int?, responseBody: Data?) -> [String: String] {
        var data = ["status": status.map(String.init) ?? "network"]
        if let code = parse(responseBody)?["code"] as? String, isErrorCode(code) {
            data["error_code"] = code
        }
        return data
    }

    /// Whether a value has the server's error code format, such as `APP-1023`.
    static func isErrorCode(_ value: String) -> Bool {
        matches(value, errorCode)
    }

    /// The path template of a URL below a watched base, or `nil` when the URL is not under one: the first
    /// segment when it is a word, and every other segment, which can be an id, a handle or a name someone
    /// chose, as `{id}`.
    func route(_ url: URL) -> String? {
        pathBelowBase(url).map(Self.template)
    }

    /// The path of a URL below a watched base, in lower case, with only what cannot be a word replaced by
    /// `{id}`, or `nil` when the URL is not under one. Used only to match configured patterns; never sent.
    func path(_ url: URL) -> String? {
        pathBelowBase(url).map(Self.shape)
    }

    /// The path of a URL below a watched base, in lower case and as called, with no value replaced, or `nil`
    /// when the URL is not under one. Used only to match `exclude`; never sent.
    func literalPath(_ url: URL) -> String? {
        pathBelowBase(url).map { Self.join($0.map { $0.lowercased() }) }
    }

    /// Names a call, or returns `nil` when it is not reported.
    ///
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - url: The URL called.
    func classify(method: String?, url: URL?) -> TelemetryApiCall? {
        let verb = (method ?? "GET").uppercased()
        guard let change = TelemetryChange(verb: verb), let url, let path = pathBelowBase(url), !path.isEmpty else {
            return nil
        }
        return name(verb: verb, change: change, path: path)
            ?? TelemetryApiCall(name: "api.call", route: Self.template(path), data: ["method": verb])
    }

    /// Names a change from its method and path segments, or returns `nil` when no rule fits.
    private func name(verb: String, change: TelemetryChange, path: [String]) -> TelemetryApiCall? {
        var route: [String] = []
        var index = 0
        // Words in front of the first collection, such as `design` in `/design/themes`.
        while index < path.count, !Self.isCollection(path[index]), Self.matches(path[index], Self.templateWord) {
            route.append(path[index].lowercased())
            index += 1
        }
        guard index < path.count, Self.isCollection(path[index]) else {
            return Self.withoutCollection(verb: verb, change: change, path: path, words: route)
        }
        var walk = TelemetryPathWalk(
            verb: verb,
            change: change,
            path: path,
            route: route,
            vocabulary: vocabulary
        )
        while true {
            if case let .named(call) = walk.collection() { return call }
        }
    }

    /// Names a call whose path has no collection, or returns `nil`.
    ///
    /// - Parameter words: The words read from the front of the path, in lower case.
    private static func withoutCollection(
        verb: String,
        change: TelemetryChange,
        path: [String],
        words: [String]
    ) -> TelemetryApiCall? {
        // `PUT /server-config/{name}` is a change to `server-config`.
        if path.count == 2, change != .create, isWord(path[0]) {
            let type = path[0].lowercased()
            return TelemetryApiCall(
                name: "\(type).\(change.rawValue)",
                route: "/\(type)/{id}",
                data: ["resource_type": type]
            )
        }
        // No resource type, only words: `POST /import` is `api.import`, `POST /import/managed` is
        // `api.import-managed`, and `PUT /maintenance` is `api.maintenance-update`. Only letter words and
        // versions such as `v2` make a name, so an id with digits, such as a client id, never does.
        let onlyWords = path.allSatisfy { isWord($0) || matches($0.lowercased(), version) }
        guard words.count == path.count, onlyWords else { return nil }
        let suffix = verb == "POST" ? "" : "-\(change.rawValue)"
        return TelemetryApiCall(name: "api.\(words.joined(separator: "-"))\(suffix)", route: join(words), data: [:])
    }

    fileprivate static func join(_ route: [String]) -> String {
        "/" + route.joined(separator: "/")
    }

    /// The path below a base in lower case, with only what cannot be a word replaced by `{id}`.
    private static func shape(_ path: [String]) -> String {
        join(path.map { matches($0, templateWord) ? $0.lowercased() : "{id}" })
    }

    /// The path template of an `api.call`: the first segment when it is a word, every later segment `{id}`.
    private static func template(_ path: [String]) -> String {
        let segments = path.enumerated()
            .map { idx, segment in
                idx == 0 && matches(segment, templateWord) ? segment.lowercased() : "{id}"
            }
        return join(segments)
    }

    /// Whether a segment is a plain word.
    fileprivate static func isWord(_ segment: String) -> Bool {
        matches(segment, word)
    }

    /// Whether a segment starts with a word of the naming scheme, such as `update-credentials`.
    fileprivate static func isChangeWord(_ segment: String) -> Bool {
        guard isWord(segment), let first = segment.lowercased().split(separator: "-").first else { return false }
        return changeWords.contains(String(first))
    }

    /// Whether a segment names a collection, such as `applications`, and is not an action.
    fileprivate static func isCollection(_ segment: String) -> Bool {
        segment.count > 2 && isWord(segment) && !isChangeWord(segment)
            && TelemetryNames.isCollection(segment.lowercased())
    }

    private static func matches(_ value: String, _ regex: NSRegularExpression?) -> Bool {
        regex?.firstMatch(in: value, options: [], range: NSRange(value.startIndex..., in: value)) != nil
    }

    /// A request or response body as a JSON object, or `nil`.
    private static func parse(_ body: Data?) -> [String: Any]? {
        guard let body, !body.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    /// The path segments of a URL below the longest watched base it falls under, or `nil`.
    private func pathBelowBase(_ url: URL) -> [String]? {
        guard let called = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let calledOrigin = Self.origin(called) else {
            return nil
        }
        let calledPath = called.percentEncodedPath
        var longest: String?
        for base in bases {
            guard let root = URLComponents(string: base), Self.origin(root) == calledOrigin else { continue }
            var prefix = root.percentEncodedPath
            while prefix.hasSuffix("/") { prefix.removeLast() }
            let under = prefix.isEmpty || calledPath == prefix || calledPath.hasPrefix(prefix + "/")
            if under, prefix.count >= (longest?.count ?? -1) { longest = prefix }
        }
        guard let longest else { return nil }
        return calledPath.dropFirst(longest.count)
            .split(separator: "/")
            .map(String.init)
    }

    /// The origin of a URL: its scheme, host and port, the default port left out.
    static func origin(_ components: URLComponents) -> String? {
        guard let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        let defaultPort = scheme == "https" ? 443 : (scheme == "http" ? 80 : nil)
        guard let port = components.port, port != defaultPort else { return "\(scheme)://\(host)" }
        return "\(scheme)://\(host):\(port)"
    }
}

/// The words of the watched APIs that the rules cannot tell from a path alone, from configuration.
struct TelemetryApiVocabulary {
    /// Sub-collections reported as an action on their parent, by change.
    let parentActions: [String: [TelemetryChange: String]]
    /// Top-level collections whose next word is a kind, in lower case.
    let kinds: Set<String>
    /// Words after a collection that start an address, in lower case.
    let addressWords: Set<String>
    /// Words that end a POST to a sub-collection as an action on the parent, in lower case.
    let actions: Set<String>
}

/// What a write does to the resource it names.
enum TelemetryChange: String {
    case create
    case delete
    case update

    init?(verb: String) {
        switch verb {
        case "POST": self = .create
        case "PUT", "PATCH": self = .update
        case "DELETE": self = .delete
        default: return nil
        }
    }
}

/// A walk down a path from one collection to the next, naming the call when it reaches what it changes.
private struct TelemetryPathWalk {
    /// What a step found: the call's name, or `nil` when it is not named, or a sub-resource to walk on to.
    enum Step {
        case named(TelemetryApiCall?)
        case subResource
    }

    let verb: String
    let change: TelemetryChange
    let path: [String]
    let vocabulary: TelemetryApiVocabulary
    var route: [String]
    /// The segment being read, a collection at the start of each step.
    var index: Int
    var parent: String?

    /// Starts at the first collection, after the words in front of it, which are already in `route`.
    init(
        verb: String,
        change: TelemetryChange,
        path: [String],
        route: [String],
        vocabulary: TelemetryApiVocabulary
    ) {
        self.verb = verb
        self.change = change
        self.path = path
        self.route = route
        self.vocabulary = vocabulary
        index = route.count
    }

    /// Reads a collection and what follows it.
    mutating func collection() -> Step {
        let collection = path[index].lowercased()
        let type = TelemetryNames.singular(collection)
        route.append(collection)
        index += 1
        let data = parent.map { ["parent_type": $0] } ?? [:]

        // The collection itself: `POST /groups`, or `PUT /flows/{id}/variables` for all of them.
        if index == path.count {
            return .named(changeOf(type: type, collection: collection, data: data))
        }

        // A configured address word starts an address: everything after it, even nothing, is the item's place,
        // never a name. `PUT /organization-units/tree/a/b` with `tree` listed is `organization-unit.update`.
        if vocabulary.addressWords.contains(path[index].lowercased()) {
            route += [path[index].lowercased(), "{path}"]
            return .named(changeOf(type: type, collection: collection, data: data))
        }

        // A change word, or a configured action, that ends a POST to a sub-collection is an action on the
        // parent: `POST /groups/{id}/members/add` is `group.member-add`. Any other word there is an id the
        // caller chose.
        if let parent, verb == "POST", index == path.count - 1, isAction(path[index]) {
            let action = path[index].lowercased()
            route.append(action)
            return named("\(parent).\(type)-\(action)", data: ["resource_type": parent, "sub_type": type])
        }
        return item(type: type, collection: collection, data: data)
    }

    /// Whether a word ending a POST to a sub-collection is an action: a change word or a configured action.
    private func isAction(_ segment: String) -> Bool {
        TelemetryApiRules.isWord(segment)
            && (TelemetryApiRules.isChangeWord(segment) || vocabulary.actions.contains(segment.lowercased()))
    }

    /// Reads an item of a collection, with the kind or the label in front of it, if any.
    private mutating func item(type: String, collection: String, data: [String: String]) -> Step {
        // A kind: the word right after a top-level collection listed in `kinds`, as in `/connections/google/{id}`
        // or `POST /connections/google`. Under any other collection the word is an item value.
        let segment = path[index]
        let isKind = parent == nil && vocabulary.kinds.contains(collection) && TelemetryApiRules.isWord(segment)
        var itemData = data

        // A label and its value in front of a sub-collection of a sub-collection, such as `ns/{namespace}` in
        // `/languages/{id}/translations/ns/{namespace}/keys`: the label is kept and the value is not.
        if parent != nil, isLabel(segment), index + 2 < path.count,
           TelemetryApiRules.isCollection(path[index + 2]) {
            route += [segment.lowercased(), "{id}"]
            index += 2
            parent = type
            return .subResource
        }

        if isKind {
            itemData["kind"] = segment.lowercased()
            route.append(segment.lowercased())
            index += 1
            if index == path.count {
                return .named(changeOf(type: type, collection: collection, data: itemData))
            }
        }

        // The item: an id, or a word that a collection or an action follows, such as `me` or `en`.
        let itemIsWord = TelemetryApiRules.isWord(path[index])
        route.append("{id}")
        index += 1
        if index == path.count {
            // `POST /<collection>/{id}` creates one at an id the caller chose.
            return .named(changeOf(type: type, collection: collection, data: itemData))
        }
        return afterItem(type: type, collection: collection, data: itemData, itemIsWord: itemIsWord)
    }

    /// Whether a segment is a plain word that labels the value after it: not a change word.
    private func isLabel(_ segment: String) -> Bool {
        TelemetryApiRules.isWord(segment) && !TelemetryApiRules.isChangeWord(segment)
    }

    /// Reads what follows an item: a sub-resource, the rest of a word item's address, or an action.
    private mutating func afterItem(
        type: String,
        collection: String,
        data: [String: String],
        itemIsWord: Bool
    ) -> Step {
        let rest = path[index...].map { $0.lowercased() }

        // A sub-resource of the item.
        if TelemetryApiRules.isCollection(path[index]) {
            parent = type
            return .subResource
        }

        // Words after an item that is itself a word, as in `/organization-units/tree/eng/backend`, can be
        // values someone chose, such as handles in a path, so they are part of the item's address and never
        // part of a name. One segment that starts with a change word, such as `/users/me/update-credentials`,
        // is still an action.
        if itemIsWord, !(rest.count == 1 && TelemetryApiRules.isChangeWord(rest[0])) {
            route.append("{path}")
            return .named(changeOf(type: type, collection: collection, data: data))
        }

        // An action on the item: `client-secret/regenerate`, `restore`, `update-credentials`, or a setting such
        // as `PUT /projects/{id}/auto-sync`.
        guard rest.allSatisfy(TelemetryApiRules.isWord) else { return .named(nil) }
        route += rest
        var all = data
        all["resource_type"] = type
        let suffix = verb == "POST" ? "" : "-\(change.rawValue)"
        return named("\(type).\(rest.joined(separator: "-"))\(suffix)", data: all)
    }

    private func named(_ name: String, data: [String: String]) -> Step {
        .named(TelemetryApiCall(name: name, route: TelemetryApiRules.join(route), data: data))
    }

    /// A create, update or delete of a collection's resource, or the parent's action for a sub-resource such
    /// as a sharing policy.
    private func changeOf(type: String, collection: String, data: [String: String]) -> TelemetryApiCall {
        let joined = TelemetryApiRules.join(route)
        if let parent, let action = vocabulary.parentActions[collection]?[change] {
            var rest = data
            rest["parent_type"] = nil
            rest["resource_type"] = parent
            return TelemetryApiCall(name: "\(parent).\(action)", route: joined, data: rest)
        }
        var all = data
        all["resource_type"] = type
        return TelemetryApiCall(name: "\(type).\(change.rawValue)", route: joined, data: all)
    }
}
