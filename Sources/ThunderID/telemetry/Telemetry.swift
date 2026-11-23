// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The auth events the SDK reports.
enum TelemetryAuthAction: String {
    case signIn = "sign-in"
    case signInFailed = "sign-in-failed"
    case signOut = "sign-out"
    case sessionExpired = "session-expired"
}

/// How an API call ended.
struct TelemetryApiOutcome {
    /// Whether it succeeded, and if not, how it failed.
    enum Result {
        case success
        /// The HTTP status, or `nil` when no response came, and the response body, read for its error code.
        case failure(status: Int?, responseBody: Data?)
    }

    let result: Result
    /// The name the API gave the call in its `X-Telemetry-Event` response header, if any.
    var event: String?

    /// A call that succeeded.
    static let success = TelemetryApiOutcome(result: .success)

    /// A call that succeeded, with the name the API gave it.
    static func success(event: String?) -> TelemetryApiOutcome {
        TelemetryApiOutcome(result: .success, event: event)
    }

    /// A call that failed, with the name the API gave it, if any.
    static func failure(status: Int?, responseBody: Data?, event: String? = nil) -> TelemetryApiOutcome {
        TelemetryApiOutcome(result: .failure(status: status, responseBody: responseBody), event: event)
    }
}

/// What a platform gives the telemetry.
struct TelemetryDependencies {
    /// The base URLs of the SDK's own API, watched for API events besides `apiEvents.apis`.
    var apiBases: [String]
    /// Reads the current user and organization.
    var identity: () async -> TelemetryIdentity
    /// Sends one encoded body. A failure is dropped.
    var send: (Data) async throws -> Void
    /// The operating system events come from.
    var system: TelemetryOS? = .current
    /// How long a batch waits before it is sent, in seconds.
    var flushInterval: TimeInterval = 5
    /// A batch whose sending has not finished by then is abandoned, in seconds.
    var sendTimeout: TimeInterval = 10
    /// Called when a batch's sending ends, even one abandoned after its timeout. Only tests set it.
    var batchEnded: (() -> Void)?
}

/// An event as it is recorded, before its identity is read.
struct TelemetryPendingEvent {
    let kind: TelemetryEventKind
    let name: String
    let route: String?
    let data: [String: String]
    let date: Date
    /// The identity, when the caller already read it, such as for a sign-out before the session is cleared.
    let identity: TelemetryIdentity?
}

/// Reports what people do in an app: screen views, API events, auth events, links that leave the app and
/// the app's own `track` calls. Every entry point returns at once: events are handed, in order, to a
/// background pipeline that batches and sends them, and a failure is dropped and never reaches the app.
final class Telemetry {
    /// A batch is sent when it reaches this many events, or after ``TelemetryDependencies/flushInterval``.
    static let batchSize = 20
    /// At most this many events wait, such as for consent; the oldest are dropped first.
    static let maxWaiting = 200
    /// The response header in which an API names the event for a call, such as `application.share`.
    static let eventHeader = "x-telemetry-event"

    let config: TelemetryConfig
    private let names: TelemetryNames
    private let rules: TelemetryApiRules
    private let inbox: AsyncStream<TelemetryCommand>.Continuation

    init(config: TelemetryConfig, dependencies: TelemetryDependencies) {
        self.config = config
        names = TelemetryNames(prefix: config.prefix)
        rules = TelemetryApiRules(
            bases: dependencies.apiBases + config.apiEvents.apis,
            parentActions: config.apiEvents.parentActions.mapValues(\.byChange),
            kinds: config.apiEvents.kinds,
            addressWords: config.apiEvents.addressWords,
            actions: config.apiEvents.actions
        )
        var continuation: AsyncStream<TelemetryCommand>.Continuation!
        let stream = AsyncStream<TelemetryCommand> { continuation = $0 }
        inbox = continuation
        let pipeline = TelemetryPipeline(config: config, dependencies: dependencies)
        Task {
            for await command in stream {
                await pipeline.handle(command)
            }
        }
    }

    deinit {
        inbox.finish()
    }

    /// Whether a configuration turns telemetry on: it has an endpoint.
    static func isEnabled(_ config: TelemetryConfig?) -> Bool {
        guard let config else { return false }
        return !config.endpoint.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Reports a screen view from its route pattern, such as `/applications/:id`.
    func page(_ pattern: String) {
        let pages = config.pages
        guard pages.enabled, !TelemetryNames.matchesAny(pattern, pages.exclude) else { return }
        add(.page, pages.names[pattern] ?? TelemetryNames.pageName(pattern), route: pattern)
    }

    /// Reports an API call the app made, when the rules name it.
    ///
    /// - Parameters:
    ///   - body: The request body, read only for the configured `skipWhen` fields and `?field` conditions;
    ///     never sent.
    ///   - outcome: Whether it succeeded, and if not, the status and the response body; and the name the API
    ///     gave it, where `none` means it is not reported.
    func api(method: String?, url: URL?, body: Data?, outcome: TelemetryApiOutcome) {
        let apiEvents = config.apiEvents
        let changesNothing = apiEvents.skipWhen.contains { TelemetryApiRules.sets(body, $0) }
        guard apiEvents.enabled, let url, !changesNothing,
              let call = rules.classify(method: method, url: url), let path = rules.path(url),
              outcome.event != "none", !isExcluded(url: url, path: path, name: call.name) else {
            return
        }
        let named = apiName(call, path: path, method: (method ?? "").uppercased(), body: body, event: outcome.event)
        // The final name is checked too, before `-failed` is added, so excluding a name stops its failures.
        guard !TelemetryNames.matchesAny(named.name, apiEvents.exclude) else { return }
        switch outcome.result {
        case .success:
            add(.api, named.name, route: named.route, data: call.data)
        case let .failure(status, responseBody):
            let failure = TelemetryApiRules.failureData(status: status, responseBody: responseBody)
            add(.api, "\(named.name)-failed", route: named.route, data: call.data.merging(failure) { _, new in new })
        }
    }

    /// Whether `apiEvents.exclude` leaves a call out, by its URL without the query, its path as called, its
    /// masked path or the rules' name.
    private func isExcluded(url: URL, path: String, name: String) -> Bool {
        let exclude = config.apiEvents.exclude
        return TelemetryNames.matchesAny(Self.withoutQuery(url), exclude)
            || rules.literalPath(url).map { TelemetryNames.matchesAny($0, exclude) } == true
            || TelemetryNames.matchesAny(path, exclude)
            || TelemetryNames.matchesAny(name, exclude)
    }

    /// The name of an API event and its route, from the first that applies: a configured name for its method
    /// and path, optionally with a body field it must set (`POST /promotions ?origin`); a configured rename of
    /// the rules' name; the name the API gave in its response header, which a configured rename keyed by that
    /// name may still change; or the rules' name. Configuration always comes before the header. A configured
    /// path names the route too, with each `*` as `{id}`.
    private func apiName(
        _ call: TelemetryApiCall,
        path: String,
        method: String,
        body: Data?,
        event: String?
    ) -> (name: String, route: String) {
        let names = config.apiEvents.names
        // A key with a body condition is more specific, so it is tried first.
        let keys = names.sorted { lhs, rhs in
            let lhsCondition = lhs.key.contains(" ?")
            let rhsCondition = rhs.key.contains(" ?")
            return lhsCondition == rhsCondition ? lhs.key < rhs.key : lhsCondition
        }
        for (key, value) in keys {
            let parts = key.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            guard parts.count > 1, parts[0].uppercased() == method, TelemetryNames.matches(path, parts[1]) else {
                continue
            }
            let condition = parts.count > 2 && parts[2].hasPrefix("?") ? String(parts[2].dropFirst()) : nil
            if let condition, !TelemetryApiRules.sets(body, condition) { continue }
            let route = parts[1].replacingOccurrences(of: "\\*\\*?", with: "{id}", options: .regularExpression)
            return (value, route)
        }
        if let renamed = names[call.name] { return (renamed, call.route) }
        if let fromApi = event.flatMap({ TelemetryNames.isEventName($0) ? $0 : nil }) {
            return (names[fromApi] ?? fromApi, call.route)
        }
        return (call.name, call.route)
    }

    /// Reports an auth event.
    ///
    /// - Parameters:
    ///   - data: Codes about it, such as an error code for a failed sign-in.
    ///   - identity: The identity, when it has to be read before the session changes.
    func auth(_ action: TelemetryAuthAction, data: [String: String] = [:], identity: TelemetryIdentity? = nil) {
        let authEvents = config.authEvents
        guard authEvents.enabled, !authEvents.exclude.contains(action.rawValue) else { return }
        add(.auth, authEvents.names[action.rawValue] ?? "auth.\(action.rawValue)", data: data, identity: identity)
    }

    /// Reports a link that leaves the app, with its host and path only. Only `http` and `https` links count.
    func link(_ url: URL) {
        let links = config.links
        guard links.enabled, let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let origin = TelemetryApiRules.origin(components), let host = components.host else {
            return
        }
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let target = origin + path
        guard !TelemetryNames.matchesAny(target, links.exclude) else { return }
        let renamed = links.names.sorted { $0.key < $1.key }.first { TelemetryNames.matches(target, $0.key) }
        let hostAndPort = components.port.map { "\(host):\($0)" } ?? host
        let data = ["host": hostAndPort, "path": TelemetryNames.templatedPath(path)]
        add(.link, renamed?.value ?? "link.open", data: data)
    }

    /// Reports an event the app names, for what is neither a screen, an API call nor a link. A name that is not
    /// `<type>.<action>` in lower-case hyphenated words drops the event, and a value that does not look like
    /// a code is left out.
    func track(_ name: String, data: [String: String] = [:]) {
        guard TelemetryNames.isEventName(name) else { return }
        add(.custom, name, data: data.filter { TelemetryNames.isCode($0.value) })
    }

    /// Sends what is waiting now, once every event reported before it is recorded.
    ///
    /// - Parameter background: Whether the app is going to the background. Events waiting for consent are
    ///   then kept rather than tried again later.
    func flush(background: Bool = false) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            if case .terminated = inbox.yield(.flush(background: background, done: done)) {
                done.resume()
            }
        }
    }

    /// ``flush(background:)``, waiting at most `seconds`: the send goes on in the background after that.
    func flush(waitingAtMost seconds: TimeInterval) async {
        let once = TelemetryOnce()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            Task {
                await self.flush()
                once.run { done.resume() }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                once.run { done.resume() }
            }
        }
    }

    private func add(
        _ kind: TelemetryEventKind,
        _ name: String,
        route: String? = nil,
        data: [String: String] = [:],
        identity: TelemetryIdentity? = nil
    ) {
        let event = TelemetryPendingEvent(
            kind: kind,
            name: names.full(name),
            route: route,
            data: data,
            date: Date(),
            identity: identity
        )
        inbox.yield(.record(event))
    }

    private static func withoutQuery(_ url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let origin = TelemetryApiRules.origin(components) else {
            return url.absoluteString
        }
        return origin + components.percentEncodedPath
    }
}

/// What the pipeline is asked to do, in the order the app asked.
enum TelemetryCommand {
    case record(TelemetryPendingEvent)
    case flush(background: Bool, done: CheckedContinuation<Void, Never>?)
}

/// Runs a closure once, whichever caller comes first.
final class TelemetryOnce {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}

/// Batches events and sends them: when a batch is full, after the flush interval, and when asked.
actor TelemetryPipeline {
    private let config: TelemetryConfig
    private let dependencies: TelemetryDependencies
    private let encoder: TelemetryEncoder
    private var queue: [TelemetryEvent] = []
    private var timer: Task<Void, Never>?
    /// The batch being sent. At most one is in flight.
    private var inFlight: Task<Void, Never>?

    init(config: TelemetryConfig, dependencies: TelemetryDependencies) {
        self.config = config
        self.dependencies = dependencies
        encoder = TelemetryEncoder(format: config.format, mapping: config.mapping)
    }

    func handle(_ command: TelemetryCommand) async {
        switch command {
        case .record(let pending):
            await record(pending)
        case let .flush(background, done):
            await flush(background: background)
            done?.resume()
        }
    }

    private func record(_ pending: TelemetryPendingEvent) async {
        var identity = pending.identity
        if identity == nil { identity = await dependencies.identity() }
        queue.append(TelemetryEvent(
            name: pending.name,
            id: UUID().uuidString.lowercased(),
            kind: pending.kind,
            timestamp: TelemetryEvent.timestamp(pending.date),
            route: pending.route,
            identity: identity ?? TelemetryIdentity(),
            system: dependencies.system,
            data: pending.data,
            context: config.context
        ))
        if queue.count > Telemetry.maxWaiting {
            queue.removeFirst(queue.count - Telemetry.maxWaiting)
        }
        if queue.count >= Telemetry.batchSize, consented() {
            await flush(background: false)
        } else {
            schedule()
        }
    }

    private func flush(background: Bool) async {
        timer?.cancel()
        timer = nil
        guard !queue.isEmpty else { return }
        guard consented() else {
            // Wait for consent: try again later, unless the app is going to the background.
            if !background { schedule() }
            return
        }
        // One batch at a time: a flush while one is in flight waits for it to end.
        while let sending = inFlight {
            await sending.value
            // The batch has ended: clear it here too, since the flush that started it may not have run again
            // yet, and waiting on an ended batch again would never let it.
            if inFlight == sending { inFlight = nil }
        }
        guard !queue.isEmpty else { return }
        // Consent can be withdrawn while the batch in flight was being sent: keep the events then.
        guard consented() else {
            if !background { schedule() }
            return
        }
        let task = sending(encoder.encodeBodies(queue), background: background)
        queue = []
        inFlight = task
        await task.value
        // Another flush may have started the next batch while this one was ending.
        if inFlight == task { inFlight = nil }
    }

    /// Starts sending `bodies`, one after another, abandoning them after the send timeout.
    private func sending(_ bodies: [TelemetryBody], background: Bool) -> Task<Void, Never> {
        let send = dependencies.send
        let timeout = dependencies.sendTimeout
        let batchEnded = dependencies.batchEnded
        let consent = config.consent
        return Task {
            let unsent = await Self.abandoning(after: timeout) { () async -> [TelemetryEvent] in
                defer { batchEnded?() }
                for (index, body) in bodies.enumerated() {
                    // A batch abandoned after its timeout sends nothing more.
                    guard !Task.isCancelled else { return [] }
                    // Consent can be withdrawn while an earlier body was being sent, such as in `each` mode:
                    // the events not sent yet wait again, and those already sent are not.
                    guard consent?() ?? true else { return bodies[index...].flatMap(\.events) }
                    // A failure is dropped: telemetry never affects the app.
                    try? await send(body.data)
                }
                return []
            }
            // Put back before the batch ends, so a flush waiting for it finds them.
            self.requeue(unsent ?? [], background: background)
        }
    }

    /// Puts back events whose sending did not start, ahead of those recorded since, as they are older. The
    /// oldest are dropped past ``Telemetry/maxWaiting``.
    private func requeue(_ events: [TelemetryEvent], background: Bool) {
        guard !events.isEmpty else { return }
        queue = events + queue
        if queue.count > Telemetry.maxWaiting {
            queue.removeFirst(queue.count - Telemetry.maxWaiting)
        }
        if !background { schedule() }
    }

    /// Runs `operation`, returning its result when it ends, or `nil` after `seconds`, whichever comes first. An
    /// operation still running then is cancelled.
    private static func abandoning<T>(
        after seconds: TimeInterval,
        _ operation: @escaping () async -> T
    ) async -> T? {
        let once = TelemetryOnce()
        return await withCheckedContinuation { (done: CheckedContinuation<T?, Never>) in
            let work = Task {
                let result = await operation()
                once.run { done.resume(returning: result) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                work.cancel()
                once.run { done.resume(returning: nil) }
            }
        }
    }

    private func schedule() {
        guard timer == nil else { return }
        let nanoseconds = UInt64(max(dependencies.flushInterval, 0) * 1_000_000_000)
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await self?.timerFired()
        }
    }

    private func timerFired() async {
        timer = nil
        await flush(background: false)
    }

    private func consented() -> Bool {
        config.consent?() ?? true
    }
}
