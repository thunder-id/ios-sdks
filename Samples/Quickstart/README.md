# Thunder iOS B2C Sample

Demonstrates a native iOS B2C flow using the ThunderSwiftUI SDK:

- Unauthenticated → embedded sign-in form (Flow Execution API)
- Authenticated → user avatar dropdown, organization switcher, editable profile sheet
- Sign-out → returns to sign-in screen

## Setup

```bash
cp Config.plist.example Sources/Config.plist
# Edit Sources/Config.plist with your Thunder base URL, client ID, and application ID
```

## Run

Open in Xcode via `Package.swift` and run on an iOS 16+ simulator or device.

## SDK used

`ThunderSwiftUI` at `sdks/thunderid-swiftui/` — depends on the `Thunder` iOS Platform SDK at `sdks/thunderid-ios/`.
