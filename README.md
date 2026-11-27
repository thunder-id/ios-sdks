![ThunderID iOS SDK](https://raw.githubusercontent.com/thunder-id/thunderid/refs/heads/main/docs/static/assets/images/readme/repo-banner-ios-sdk.png)

iOS SDK for ThunderID. Provides authentication and user management for native iOS and macOS applications.

- [Quickstart](https://thunderid.dev/docs/next/getting-started/connect-your-application/ios/)
- [API reference](https://thunderid.dev/docs/next/sdks/ios/overview/)
- [Sample app](https://github.com/thunder-id/samples/tree/main/quickstarts/quickstart-ios)

## Installation

### Swift Package Manager

```swift
.package(url: "https://github.com/thunder-id/ios-sdks", branch: "main")
```

> [!NOTE]
> To pin to a release instead of tracking `main`, replace `branch: "main"` with `from: "x.x.x"`, using the latest version: ![GitHub release](https://img.shields.io/github/v/release/thunder-id/ios-sdks)

## Other OpenID Connect providers

Redirect sign-in (`signInURL(options:)` and `handleRedirectCallback(url:)`) works with any standards-compliant OpenID Connect provider. Set `baseUrl` to the provider's root URL, such as its tenant URL, and `endpoints.wellKnown` to the provider's discovery URL:

```swift
ThunderIDConfig(
    baseUrl: "https://api.asgardeo.io/t/<org>",
    clientId: "<client id>",
    afterSignInUrl: "myapp://callback",
    endpoints: .init(
        wellKnown: "https://api.asgardeo.io/t/<org>/oauth2/token/.well-known/openid-configuration"
    )
)
```

- The SDK reads the provider's metadata from `endpoints.wellKnown` and uses the authorization, token, JWKS, userinfo and revocation endpoints it advertises. `endpoints.wellKnown` must be an HTTPS URL. When it is not set, the metadata is read from `{baseUrl}/.well-known/openid-configuration`, so it can be left out when the provider's issuer is its root URL.
- Setting `baseUrl` to the provider's issuer URL, with no `endpoints.wellKnown`, also works.
- When the metadata cannot be read, or omits an endpoint, the SDK uses the ThunderID path under `baseUrl`, such as `{baseUrl}/oauth2/token`.
- An ID token's `iss` is checked as OpenID Connect Discovery requires. The expected issuer is the discovery URL without `/.well-known/openid-configuration`, or `baseUrl` when `endpoints.wellKnown` is not set. When the metadata names that issuer, with or without one trailing slash, `iss` must match the metadata's issuer exactly. When `endpoints.wellKnown` does not end with `/.well-known/openid-configuration`, `iss` must match the issuer in the metadata, and the token is refused when the metadata cannot be read.
- Build the sign-in URL with `signInURL(options:)`, which reads the metadata first. `buildSignInURL(options:)` is synchronous, so it uses the advertised authorization endpoint only once the metadata has been read, and `{baseUrl}/oauth2/authorize` before that.
- Sign-in bounded to an organization unit, app-native sign-in and the management operations are ThunderID features, and keep their ThunderID paths.

## Sign-in on a backend

Set `endpoints.backend` to hand sign-in to a backend the app owns (the Backend for Frontend pattern of RFC 10017). The backend runs the OAuth flow and keeps the tokens, and the app only holds an opaque session handle.

```swift
ThunderIDConfig(
    baseUrl: "https://app.example.com",          // the backend
    endpoints: .init(backend: .init(
        session: "/auth/session",                 // relative: resolved against baseUrl
        proxy: "/auth/api"                        // API calls go here; the backend maps them to the API
    ))
)
```

- `baseUrl` is the backend's base URL, and it must use HTTPS.
- Each endpoint is either a path that starts with `/`, resolved against `baseUrl`, or an absolute HTTPS URL, used as is. Unset endpoints default to paths under `/api/auth`.
- API calls go to `{baseUrl}{proxy}`: a path such as `/users` is sent to `https://app.example.com/auth/api/users`, and a URL already under the proxy is sent as it is. The SDK's own calls, `/users/me` and the management operations, go there too. The backend maps the proxy to the API from its own configuration, so the app never needs the API's address.
- `getGrantedPermissions()` reads the permissions from the backend's session (`scope`), never from a token.

## Organizations

The signed-in user's organization units, and signing in to one of them:

- `getAccessibleOrganizationUnits(scope:limit:offset:)` lists the units the user can access (`/users/me/ous`); `getCurrentOrganizationUnit()` reads the session's `ouId`, `ouHandle` and `ouName` claims, for display only.
- `SignInOptions(organizationUnitId:)` bounds a redirect sign-in to a unit (`/ou/{ouId}/oauth2/authorize`, and its code is redeemed at `/ou/{ouId}/oauth2/token`). In app-native mode, `EmbeddedFlowRequestConfig(organizationUnitId:)` or `SignIn(applicationId:organizationUnitId:)` sends `ouId` when the flow starts. On a backend, it is passed to the backend's sign-in endpoint as `ouId`.
- `switchOrganizationUnit(_:options:)` signs in again bounded to another unit: with a device secret (the `device_sso` scope) it exchanges it at the unit's token endpoint with no browser, dropping a secret the server refuses with `invalid_request` or `invalid_grant`; when there is none or the exchange fails, it opens the unit's authorization URL through `options.authorize`, or, in app-native mode, starts the bounded flow with the SSO session handles that earlier flow steps returned in `sessionData`, and returns `.signInRequired` when the flow needs the user. The device secret and the kept session handles survive a switch, and a sign-out clears them. A failed switch leaves the session as it was; an unknown unit and one the application cannot be used from both fail with `ORGANIZATION_UNIT_UNAVAILABLE`.
- On a backend, `switchOrganizationUnit` sends `POST {ouSwitch}?ouId=<unit id>` with `{"ouId": "<unit id>"}` as a JSON body (`endpoints.backend.ouSwitch`, `/api/auth/switch` by default), and reads the session again, with no browser. The backend switches the session it holds and answers `200`, or refuses with an OAuth `error`. When that error says the user has to sign in (`interaction_required`, `login_required`, `consent_required`, `account_selection_required`), or the answer is `401`, the switch opens the unit-bounded sign-in through `options.authorize` instead, when there is one. A `session_expired` refreshes the session once and retries.
- `OrganizationUnitSwitcher` and `BaseOrganizationUnitSwitcher` show the current unit in a field that opens a menu of the units, with their handles, a check on the current one and paging, and switch to the one picked (`onSelect` lets the app take over). The sign-in flow components render a Resolve OU step from the server's description: a typed unit before sign-in, a picker of the eligible units after.
- `ProjectList`, `ProjectCreate`, `ProjectDetails` and `ProjectSwitcher` manage projects (Control Plane only). `ProjectSwitcher` sets `ThunderIDState.currentProject`, kept per vendor; it is client-side context, not a sign-in. A project is not an organization unit: only applications and agents take one. `ApplicationList` and `AgentList` list the current project's applications and agents (an explicit `projectId` wins; the server combines a project with no attribute filter, so `AgentList` hides its search while a project applies), and `ApplicationCreate` and `AgentCreate` create in the project when the app passes no organization unit. Every other component keeps its own organization unit default (the signed-in user's unit).
- `OrganizationUnitList`, `OrganizationUnitCreate` and `OrganizationUnitDetails` manage organization units, their children and what they hold. `SharingPolicies` lists and, when `editable`, edits the sharing policies of a user, application, role or flow, with an organization unit's overlay rules when `ouId` is given.

## Optional grants

- **Pushed authorization requests (RFC 9126).** Set `pushedAuthorizationRequests: true`, or let the server's metadata require it, and build the sign-in URL with `signInURL(options:)`: it posts the request to `/oauth2/par` and authorizes with the returned `request_uri`. `buildSignInURL(options:)` cannot push, so it refuses while `pushedAuthorizationRequests` is on.
- **CIBA.** `initiateCIBA(options:)` and `pollCIBA(authReqId:interval:)`, for a public client registered with `token_endpoint_auth_method` `none`. A configuration that holds a `clientSecret` is refused with `UNSUPPORTED_OPERATION`: an app cannot keep a secret, so a confidential client's CIBA is unsupported here. The endpoint comes from the server's metadata (`ENDPOINT_NOT_ADVERTISED` when it names none).
- **Device authorization (RFC 8628).** The device side, `startDeviceAuthorization()` and `pollDeviceAuthorization(deviceCode:interval:)`, is in the `ThunderID` core, which also builds for tvOS 16; `ThunderIDSwiftUI` is iOS and macOS only, and browser sign-in is not available on tvOS. The device code is never shown or logged. The user side, `verifyDeviceCode(userCode:applicationId:)`, runs the server's `DEVICE_GRANT` flow in app-native mode; the `DeviceGrant` component drives it, from the code (typed, or handed over from a scanned verification URI) to the approved, denied or expired outcome.

## Telemetry

Set `telemetry` to report how people use the app to an endpoint you configure. It is off until `telemetry.endpoint` is set, and an endpoint that is not an HTTPS URL leaves it off.

```swift
ThunderIDConfig(
    baseUrl: "https://id.example.com",
    clientId: "app",
    telemetry: TelemetryConfig(endpoint: "https://collector.example.com/v1/logs", prefix: "acme")
)
```

- API events come from every write through the SDK, the management operations included, named from the method and path alone, the same way for any REST API: `POST /applications` is `application.create`, `PUT` or `PATCH /applications/{id}` is `application.update` and `DELETE /roles/{id}` is `role.delete`. Words in front of the first collection are skipped (`POST /design/themes` is `theme.create`), a sub-resource is named for itself with `parent_type`, a change word (`add`, `create`, `delete`, `remove`, `update`) ending a POST to a sub-collection is an action on the parent (`POST /groups/{id}/members/add` is `group.member-add`), and words after an id are an action on the item (`POST /applications/{id}/client-secret/regenerate` is `application.client-secret-regenerate`). A path of words only is named from them (`POST /import/managed` is `api.import-managed`). Any other write is `api.call` with its method and a path template that keeps only the first segment, every later segment `{id}`. A failure ends in `-failed` and carries the HTTP status and the server's error code, never the message. Reads are not reported, and no request or response body is sent. Everything specific to an API comes from `apiEvents`: `kinds` (top-level collections whose next word is a kind, such as `connections`), `addressWords` (words after a collection that start an address, such as `tree`), `actions` (more words that end a POST to a sub-collection as an action, such as `suspend`), `exclude` (matched against the URL, the path as called, the path with values replaced, and the names; excluding a name also stops its `-failed` form), `skipWhen` (body fields such as `dryRun` that mean a call changes nothing), `parentActions` (sub-collections reported as an action on their parent, such as `sharing-policies` as `share`), and `names`, keyed by a method and path (`"POST /gateways/*/apply"`), optionally with a body field it must set (`"POST /gateways/*/apply ?origin"`), or by a name to rename it. A configured path name comes first, then a rename of the rules' name, then a name the API gives in its `X-Telemetry-Event` response header (which a rename keyed by that name may still change; `none` leaves the call out), then the rules' name. `apiEvents.apis` watches more APIs with the same rules; a call is read below the longest watched base it falls under.
- Auth events: `auth.sign-in` once per sign-in session (not again on a restart, a token refresh or an organization switch), `auth.sign-in-failed` with its error code, `auth.sign-out` and `auth.session-expired`.
- Screen views: `.telemetryScreen("applications/:id")` on a view, or `trackPageView(_:)`. `applications` is `application.list-view` and `applications/:id` is `application.detail-view`.
- Links that leave the app: `.telemetryLinks()` reports the links opened through SwiftUI's `openURL` below it, and `trackLink(_:)` any other, with the host and the path only: the first path segment when it is a plain word, every later segment `{id}`. The sign-in components' links are reported on their own.
- `track(_:data:)` reports what is none of the above. A name that is not lower-case `<type>.<action>` drops the event, and a value longer than 64 characters or holding `@`, `?`, `#`, whitespace or `://` is left out.
- Events carry codes only: names, route patterns and path templates, ids, error codes, the `context` codes and the operating system and its version. They are sent as OTLP/HTTP JSON log records (`format: .otlp`, the default), as they are (`.json`), or reshaped by a `mapping` template. They go in batches of 20 or every 5 seconds, and when the app moves to the background, one batch at a time; a send that has not finished in 10 seconds is abandoned, and a failed send is dropped and never reaches the app. `consent` holds them in memory, at most 200, until it returns `true`.
- The endpoint gets the app's access token only when it shares the origin of `baseUrl` and sign-in does not run on a backend. `token: .fixed(_:)` sends that token instead, and `token: .disabled` sends none.

## Playground

[`Playground/`](Playground) is a SwiftUI app for trying every SDK capability from source: capability checks, a component explorer with generated SwiftUI snippets, a session inspector and an SDK event log. See [Playground/README.md](Playground/README.md) to run it against a local ThunderID server.

## Contributing

Please refer to the [Contributing Guide](https://thunderid.dev/community/overview) for the different ways to contribute to this project and the relevant guidelines.

For code contributions, refer to the [Contributing Code](https://thunderid.dev/community/contributing/contributing-code/prerequisites) section for details on the prerequisites and instructions for running ThunderID in development mode.

## License

This project is licensed under the [Apache License 2.0](https://github.com/thunder-id/thunderid/blob/main/LICENSE).
