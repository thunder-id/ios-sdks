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
- The **Team ID** and **Bundle ID** registered on the ThunderID application's attestation settings to
  match the ones the app is signed with. ThunderID derives the expected App ID from
  `<TeamID>.<BundleID>` and rejects a token whose attested App ID differs.

The `Attestation-Token` header carries the base64-encoded App Attest attestation object exactly as
`DCAppAttestService.attestKey` returns it — do not wrap it in a JSON envelope. The challenge should
come from the server in production; this sample generates it locally to exercise the SDK hook.

## Run

Open in Xcode via `Package.swift` and run on an iOS 16+ simulator or device.

## SDK used

`ThunderIDSwiftUI` at `sdks/thunderid-swiftui/` — depends on the `ThunderID` iOS Platform SDK at `sdks/thunderid-ios/`.
