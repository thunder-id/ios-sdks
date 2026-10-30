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

## Playground

[`Playground/`](Playground) is a SwiftUI app for trying every SDK capability from source: capability checks, a component explorer with generated SwiftUI snippets, a session inspector and an SDK event log. See [Playground/README.md](Playground/README.md) to run it against a local ThunderID server.

## Contributing

Please refer to the [Contributing Guide](https://thunderid.dev/community/overview) for the different ways to contribute to this project and the relevant guidelines.

For code contributions, refer to the [Contributing Code](https://thunderid.dev/community/contributing/contributing-code/prerequisites) section for details on the prerequisites and instructions for running ThunderID in development mode.

## License

This project is licensed under the [Apache License 2.0](https://github.com/thunder-id/thunderid/blob/main/LICENSE).
