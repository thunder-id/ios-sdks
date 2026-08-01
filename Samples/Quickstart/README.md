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
- The **Team ID** and **Bundle ID** registered on the ThunderID application's attestation settings to
  match the ones the app is signed with. ThunderID derives the expected App ID from
  `<TeamID>.<BundleID>` and rejects a token whose attested App ID differs.

The `Attestation-Token` header carries the base64-encoded App Attest attestation object exactly as
`DCAppAttestService.attestKey` returns it — do not wrap it in a JSON envelope. The challenge should
come from the server in production; this sample generates it locally to exercise the SDK hook.

### Passkeys (WebAuthn)

Passkey registration/authentication via `ASAuthorizationPlatformPublicKeyCredentialProvider`
requires the app's relying party ID to be backed by a real **Associated Domain**, not `localhost`.
Without this, `ASAuthorizationController` fails immediately with
`Error Domain=com.apple.AuthenticationServices.AuthorizationError Code=1004`.

This sample ships `Sources/Quickstart.entitlements` with a placeholder
`webcredentials:your-thunderid-domain.example` entry. To exercise passkeys end-to-end:

1. Replace the placeholder domain in `Sources/Quickstart.entitlements` with the domain your
   ThunderID server is actually reachable at (it must serve valid HTTPS — self-signed certs and
   `localhost` will not work).
2. Host an `apple-app-site-association` file at
   `https://<that-domain>/.well-known/apple-app-site-association` declaring this app's Team ID and
   `PRODUCT_BUNDLE_IDENTIFIER` (`dev.thunderid.Quickstart`) under `webcredentials.apps`.
3. Make sure the server's passkey `rp.id` matches that same domain — the SDK
   (`PasskeyAuthSession`) passes whatever `rp.id` the server returns straight through to
   `ASAuthorizationPlatformPublicKeyCredentialProvider`.
4. Set a `DEVELOPMENT_TEAM` and enable the **Associated Domains** capability for the target in
   Xcode (Signing & Capabilities) so the entitlement is actually applied to the build.

Exposing a local ThunderID instance under a real, HTTPS-reachable domain (e.g. via a tunnel) is
left to you — this sample only wires up the entitlement/documentation, not the tunnel itself.

## Run

Open in Xcode via `Package.swift` and run on an iOS 16+ simulator or device.
