![ThunderID iOS SDK](https://raw.githubusercontent.com/thunder-id/thunderid/refs/heads/main/docs/static/assets/images/readme/repo-banner-ios-sdk.png)

iOS SDK for ThunderID. Provides authentication and user management for native iOS and macOS applications.

- [Quickstart](https://thunderid.dev/docs/next/getting-started/connect-your-application/ios/)
- [API reference](https://thunderid.dev/docs/next/sdks/ios/overview/)
- [Sample app](https://github.com/thunder-id/samples/tree/main/quickstarts/ios)

## Installation

### Swift Package Manager

```swift
.package(url: "https://github.com/thunder-id/ios-sdks", branch: "main")
```

> [!NOTE]
> To pin to a release instead of tracking `main`, replace `branch: "main"` with `from: "x.x.x"`, using the latest version: ![GitHub release](https://img.shields.io/github/v/release/thunder-id/ios-sdks)

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
- `switchOrganizationUnit(_:options:)` signs in again bounded to another unit: with a device secret (the `device_sso` scope) it exchanges it at the unit's token endpoint with no browser; otherwise it opens the unit's authorization URL through `options.authorize`, or, in app-native mode, starts the bounded flow and returns `.signInRequired` when the flow needs the user. A failed switch leaves the session as it was; an unknown unit and one the application cannot be used from both fail with `ORGANIZATION_UNIT_UNAVAILABLE`.
- `OrganizationUnitSwitcher` and `BaseOrganizationUnitSwitcher` list the units, mark the current one, and switch on a tap (`onSelect` lets the app take over). The sign-in flow components render a Resolve OU step from the server's description: a typed unit before sign-in, a picker of the eligible units after.
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
