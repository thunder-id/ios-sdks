# ThunderID iOS B2C Sample

Demonstrates a native iOS B2C flow using the ThunderIDSwiftUI SDK:

- Unauthenticated → embedded sign-in form (Flow Execution API)
- Authenticated → user avatar dropdown, organization switcher, editable profile sheet
- Sign-out → returns to sign-in screen

## Setup

```bash
cp Config.plist.example Sources/Config.plist
# Edit Sources/Config.plist with your ThunderID base URL, client ID, and application ID
```

### Apple App Attest attestation (optional)

If the application enforces platform attestation, set `THUNDERID_ATTESTATION_ENABLED` to `true` in
`Sources/Config.plist`, then rebuild. When enabled, the sample mints a token via
`AppAttestTokenProvider` (Apple App Attest) and sends it with every native flow-initiate request.

Testing this end-to-end requires:
- A **physical device** — App Attest is unavailable in the simulator.
- A signing team and the **App Attest capability** enabled on the target, so Xcode adds the
  `com.apple.developer.devicecheck.appattest-environment` entitlement.
- A server that issues the App Attest challenge and verifies the attestation/assertion with Apple.
  This sample generates the challenge locally to exercise the SDK hook; point
  `AppAttestTokenProvider` at your challenge endpoint before relying on it in production.

## Run

Open in Xcode via `Package.swift` and run on an iOS 16+ simulator or device.

## SDK used

`ThunderIDSwiftUI` at `sdks/thunderid-swiftui/` — depends on the `ThunderID` iOS Platform SDK at `sdks/thunderid-ios/`.
