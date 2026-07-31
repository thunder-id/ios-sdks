# ThunderID iOS Quickstart

ThunderID iOS Quickstart demonstrates the full authentication lifecycle using the `ThunderID iOS` SDK.

**Flow demonstrated:**
1. App opens → unauthenticated state (sign-in screen)
2. User initiates sign-in / sign-up → SDK starts app-native Flow Execution
3. User completes the flow and logs in to ThunderID
4. Successful → authenticated state with profile information, token debugging, and sign-out button.
5. User taps Sign Out → session terminated, returns to sign-in screen

## Prerequisites

- Xcode 15+
- A running ThunderID instance

## Setup

```bash
cp Config.plist.example Sources/Config.plist
# Edit Sources/Config.plist with your ThunderID base URL and application ID
```

### Configuration

> [!NOTE]
> This sample uses app-native authentication (Flow Execution API), so only the base URL and application ID are required — no OAuth2 client ID or redirect URIs.

| Variable | Description |
|----------|-------------|
| `THUNDERID_BASE_URL` | Base URL of your ThunderID server (HTTPS) |
| `THUNDERID_APP_ID` | Application UUID from ThunderID console |


💡 `Sources/Config.plist` is gitignored. Never commit real credentials.

### Attestation via Apple App Attest (optional)

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
