# ThunderID iOS Playground

A SwiftUI app for exercising every capability of the ThunderID iOS SDK from source. It depends on
`ThunderID` and `ThunderIDSwiftUI` through a local package reference to the repository root, so it
always runs the SDK code in your checkout. For a minimal app to copy from, use the
[iOS quickstart](https://github.com/thunder-id/samples/tree/main/quickstarts/ios) instead.

The app has four tabs:

- **Checks**: capability checks that call the real SDK (system browser sign-in, app-native sign-in,
  passkey, sign-out, redirect callback, token refresh, Keychain storage, user info, translations),
  with run one or run all, a pass/fail reason per check, a summary ring and the server's health.
  Capabilities the iOS SDK has no API for (biometric unlock, organizations, theming) are shown as
  unavailable with the reason. Checks that need you (a browser sheet, a sign-in form, ending the
  session) run only when tapped; Run all covers the rest.
  - **Management**: the management endpoints, groups (`groups.list/get`), group members,
    roles (`roles.list/get`), role assignments (with the `type` filter), the signed-in user's
    groups and the user types, agent types, and an agent's groups and roles. These only read.
    **Group and role writes** is tap-only because it changes the server: it creates a
    `playground-*` group, adds and removes a user, creates a role assigned to the group, removes
    and re-adds the assignment, then deletes both, cleaning up even when a step fails. The read
    checks remember the first group, role, user and agent they find, and the explorer's live
    stories start from those IDs.
  - **Permissions**: `ThunderIDPermissions.fromAccessToken` and `has` on tokens built in the app
    (no session needed), and **Granted permissions**, which compares `getGrantedPermissions()`,
    the token itself and the SwiftUI `GrantedPermissions` object.
  - A card under the summary lists where `baseUrl` and each management collection resolve, and
    whether each came from an override or the `{baseUrl}/{collection}` default. The **Management
    endpoints** check confirms that
    against the URLs the SDK really builds, using a probe `fetcher` that records each request
    and stops it before it leaves the device (signed in only, since the SDK attaches the token
    first).
- **Components**: a component explorer for the ThunderIDSwiftUI components. Pick a component and a
  story, edit its props under Controls, preview it in light or dark, and copy the SwiftUI snippet
  generated from the current props under Code. The admin components (`UserList`, `UserDetails`,
  `UserCreate`, `GroupList`, `GroupCreate`, `GroupMembers`, `RoleList`, `RoleCreate`,
  `RolePermissions`, `RoleAssignments`, `AgentList`, `AgentDetails`, `AgentCreate`) are under the
  `Admin ·` groups. Their Sample, Loading, Empty, Error and Submitting stories render the `Base*`
  view with sample records (members and assignments can be added and removed locally); Live
  renders the connected view against the management API with the signed-in user's token. Live
  create stories create real records.
- **Session**: the signed-in user, an access token countdown, refresh and sign out, and tabs for
  the tokens (reveal and copy), the decoded claims, the granted permissions and recent events.
  Permissions lists what `GrantedPermissions` reads from the token, probes the management
  permissions the admin components need with `can(_:)`, and lets you test any permission.
- **Logs**: everything the playground asked the SDK to do and what came back, including every
  write the SDK makes to the Keychain (key names only).

## Prerequisites

- Xcode 16 or later, iOS 16 or later (simulator or device)
- A ThunderID server. To run one locally, follow
  [Get started](https://thunderid.dev/docs/next/getting-started/); it listens on
  `https://localhost:8090` with a self-signed certificate. The SDK accepts that certificate from a
  loopback host, and the iOS Simulator reaches the host Mac's `localhost` directly. On a device,
  point the base URL at your Mac's address and trust the server certificate on the device.

## Set up an application

In the ThunderID Console, create a **mobile** application and note its ID.

- For **app-native sign-in** (the `SignIn` component and the passkey check), the application ID is
  enough. Mobile applications must prove their identity with App Attest before they can start a
  flow, which the simulator cannot do; for local development, enable attestation dev mode on the
  application.
- For **system browser sign-in**, also give the application an OAuth client with the
  authorization code grant, PKCE, a public client, and the redirect URI
  `dev.thunderid.playground://callback`. The app registers the `dev.thunderid.playground` URL
  scheme in `Info.plist`.

## Configure

```bash
cp Sources/Config.plist.example Sources/Config.plist
```

| Key | Value |
|---|---|
| `THUNDERID_BASE_URL` | Server URL, for example `https://localhost:8090` |
| `THUNDERID_APPLICATION_ID` | The application ID, for app-native sign-in |
| `THUNDERID_CLIENT_ID` | The OAuth client ID, for system browser sign-in |
| `THUNDERID_AFTER_SIGN_IN_URL` | Redirect URI, `dev.thunderid.playground://callback` |
| `THUNDERID_AFTER_SIGN_OUT_URL` | Where to go after sign-out |
| `THUNDERID_SCOPES` | Space-separated scopes, `openid profile email` by default |

These management endpoint keys are optional. Without them every collection is
`{THUNDERID_BASE_URL}/{collection}`, which is what the SDK does when `ThunderIDConfig.endpoints`
is empty.

| Key | Value |
|---|---|
| `THUNDERID_ENDPOINT_APPLICATIONS` | Full collection URL for `endpoints.applications` |
| `THUNDERID_ENDPOINT_USERS` | `endpoints.users` |
| `THUNDERID_ENDPOINT_USER_TYPES` | `endpoints.userTypes` |
| `THUNDERID_ENDPOINT_GROUPS` | `endpoints.groups` |
| `THUNDERID_ENDPOINT_ROLES` | `endpoints.roles` |
| `THUNDERID_ENDPOINT_AGENTS` | `endpoints.agents` |
| `THUNDERID_ENDPOINT_AGENT_TYPES` | `endpoints.agentTypes` |

These keys can also be passed as launch arguments, which win over `Config.plist`, for example
`-THUNDERID_ENDPOINT_GROUPS https://localhost:9090/groups`.

`Config.plist` is gitignored. Without it the app still opens against `https://localhost:8090`
and each check explains what is missing.

## Run

Open `Playground.xcodeproj` in Xcode, pick a simulator and run the `Playground` scheme. Or from
the command line:

```bash
xcodebuild -project Playground.xcodeproj -scheme Playground \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Launch arguments, handy for screenshots: `-tab Components` (or `Session`, `Logs`) opens that tab,
`-runAll YES` runs every automatic check once the SDK has initialized, `-showEndpoints YES`
expands the endpoints card, `-component groupMembers` (any component ID) opens that component,
and `-sessionTab permissions` opens that inner Session tab.

The playground is also a Swift package, which is how CI type-checks it against the SDK:

```bash
swift build
```

## Custom rendering

Every admin view, `Base*` and connected, takes an optional `content` closure, the same pattern as `BaseSignIn`, and
renders it in place of its own UI. The closure gets the view's state: `AdminListState` (rows, paging and selection),
`NamedResourceFormState` and the other form states (bindings and `submit`), or the details states (the record and its
actions). The Components tab's **Custom rendering** group draws `UserList` as custom rows with a pager,
`GroupCreate` as plain SwiftUI fields bound to the state, and `UserDetails` as a profile card. Open one directly with
`-component customUserList` (or `customGroupCreate`, `customUserDetails`).

## Notes

- The SDK has no event emitter, so the log is recorded around each SDK call, from the storage
  adapter the playground hands the SDK through `ThunderIDConfig.storage`, and from changes to
  `ThunderIDState`.
- The SDK exposes no public accessor for the ID token, refresh token or expiry, so the session
  inspector reads them back through that storage adapter. The token refresh check drops the
  stored expiry so the next `getAccessToken()` runs the refresh grant, since there is no public
  "refresh now" call. App-native sign-in stores only an access token, so token refresh needs a
  system browser session.

### SDK gaps found while adding the management screens

- The resolved management URLs are internal (`ManagementTransport`), so the playground mirrors
  the `endpoints[field] ?? "{baseUrl}/{collection}"` rule and checks it against captured
  requests. A public accessor would remove the need for that mirror.
- `getAccessToken()` (and so `getGrantedPermissions()` and `GrantedPermissions.refresh()`)
  force-unwraps the token refresher, which `initialize(config:)` assigns after the config. Calling
  it while initialization is in flight crashes instead of throwing, so the Permissions tab waits
  for `ThunderIDState.isInitialized`.
- The management models (`ManagedGroup`, `RoleSummary`, `Role`, `ManagedUser`, `BasicAgent`,
  `Agent`, `MembershipGroup`) have no public initializers, so the `Base*` samples are decoded
  from JSON.
- There is no permission-gated wrapper (a `SignedIn`-style guard on `GrantedPermissions.can`),
  and the admin components do not hide actions the token cannot perform; they show the server's
  403 as an error.
- There is no API to list organization units, so create components rely on the `ouId` claim or
  the user profile (`ouId` control to override).
