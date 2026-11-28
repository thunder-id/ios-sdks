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

## App-native sign-in

`SignIn(applicationId:)` and `signIn(payload:request:)` run the application's flow in the app. Set both `applicationId` and `clientId`: when a flow completes, the SDK exchanges its assertion at the token endpoint (`urn:ietf:params:oauth:grant-type:token-exchange`, no scope) for the access token it keeps, and keeps the assertion as the ID token. The application needs that grant type. Sign-in, sign-up and the embedded organization unit switch do not start a flow without a `clientId`. An application without the grant fails with `INVALID_CONFIGURATION`, and the previous session, if any, stays.

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

## Credential change and recent sign-in

`updateUserCredentials(attribute:currentValue:newValue:)` sets one of the signed-in user's own credentials (`POST /users/me/update-credentials` with `{name, currentValue, newValue}`), and the `ChangeCredential` component drives it.

- When the user holds the credential, the server checks `currentValue` against it. A missing value fails with the server code `USR-1047`, and a wrong one with `USR-1048`. The code is in the error's `serverError.code`, and `message` is the server's readable message.
- When the user does not hold it yet, leave `currentValue` empty. The server then asks for a recent sign-in, as it does for a profile update that changes an `email` or `mobile` attribute.
- A blank credential name or an empty new value fails with `INVALID_INPUT` before any request.
- Replacing a credential the user holds revokes the user's tokens, including the one the SDK holds, so the user signs in again afterwards.

When the sign-in is too old, the call fails with `STEP_UP_REQUIRED`, and the error's `authenticationChallenge` carries `maxAge`, read from the `WWW-Authenticate` header (RFC 9470) or, when the header is missing, from the response body (`AUTH-4011`).

- `reauthenticate(maxAge:options:)` signs the same user in again in redirect mode: an authorization request with `max_age` (or `prompt=login`), the session's ID token as `id_token_hint`, PKCE, `state` and `nonce`, through an `ASWebAuthenticationSession` (or `options.authorize`). The new ID token must carry the same `sub`; otherwise the session stays as it was. It never refreshes to meet the challenge. With sign-in on a backend, or for a session from an app-native sign-in, it fails with `UNSUPPORTED_OPERATION`. `reauthenticationMethod()` says which way applies: `.browser`, `.flow` or `.unavailable`.
- For a session from an app-native sign-in, run the sign-in flow again with `EmbeddedFlowRequestConfig(applicationId:reauthentication: true, maxAge:)`. The flow starts with `maxAge` and the kept SSO session handles, so the server asks the user again when the sign-in is older. When it completes, its assertion is exchanged and replaces the session only when it names the signed-in user; another user fails with `AUTHENTICATION_FAILED` and the session stays.
- `SignInOptions(maxAge:idTokenHint:extra:)` sends `max_age`, `id_token_hint` and any other parameter with a redirect sign-in. A parameter in `extra` does not replace one the SDK sets.
- `ChangeCredential` and `UserProfile` handle the challenge themselves: they keep the pending change in memory, sign the user in again (the browser sheet in redirect mode, or a sheet that runs the sign-in flow for an app-native session), and retry once. When the retry is refused again or the sign-in fails, they show a translated error. When the app shows `BaseChangeCredential` or `BaseUserProfile` in its own sheet, apply `.presentsReauthentication()` to that sheet's content so the sign-in sheet can show over it. Pass `onReauthenticationRequired` to run the sign-in yourself instead.

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

## Playground

[`Playground/`](Playground) is a SwiftUI app for trying every SDK capability from source: capability checks, a component explorer with generated SwiftUI snippets, a session inspector and an SDK event log. See [Playground/README.md](Playground/README.md) to run it against a local ThunderID server.

## Contributing

Please refer to the [Contributing Guide](https://thunderid.dev/community/overview) for the different ways to contribute to this project and the relevant guidelines.

For code contributions, refer to the [Contributing Code](https://thunderid.dev/community/contributing/contributing-code/prerequisites) section for details on the prerequisites and instructions for running ThunderID in development mode.

## License

This project is licensed under the [Apache License 2.0](https://github.com/thunder-id/thunderid/blob/main/LICENSE).
