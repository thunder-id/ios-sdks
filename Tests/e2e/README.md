# Quickstart E2E

Maestro flows that drive the [Quickstart sample](https://github.com/thunder-id/samples/tree/main/quickstarts/quickstart-ios)
through real authentication against a real ThunderID server on an iOS Simulator. The flows live in [`flows/`](./flows); the
scripts alongside them get a server into the right state to run against.

## Running locally

```bash
# Everything: start a server, provision it, build and install the sample, run the flows
./run-e2e.sh

# Iterate faster once the server is up and the sample is installed
./run-e2e.sh --skip-server --skip-build

# Run a single flow
./run-e2e.sh flows/signin.yaml
```

## Where the sample comes from

The sample lives in the [thunder-id/samples](https://github.com/thunder-id/samples) repository
and depends on the published SDK release. [`scripts/prepare-sample.sh`](./scripts/prepare-sample.sh)
fetches it, copies `quickstarts/quickstart-ios` to `.quickstart/`, and repoints its SDK dependency at this
checkout, so the suite always tests the SDK source in front of it. `run-e2e.sh` calls it unless
both the server and build stages are skipped.

| Variable | Default | Purpose |
|---|---|---|
| `THUNDERID_SAMPLES_DIR` | unset | Use an existing local checkout of the samples repository instead of cloning |
| `THUNDERID_SAMPLES_REPO` | `https://github.com/thunder-id/samples.git` | Repository to clone into `.samples/` |
| `THUNDERID_SAMPLES_REF` | `main` | Branch, tag, or commit to clone |

```bash
# Test against a local samples branch
THUNDERID_SAMPLES_DIR=~/src/samples ./run-e2e.sh
```

Every stage is idempotent. A server that is already serving on `:8090` is reused rather than
restarted, and provisioning re-applies cleanly over an existing application and user.

## What gets provisioned

| Resource | Value |
|---|---|
| Application | `019e5b10-1001-7a2b-9c3d-4e5f60718293` (`Mobile Quickstart E2E App`) |
| Test user | `e2e_mobile_user` / `TestPassword@123` |

The application is declared in
[`quickstarts/quickstart-ios/thunderid-config/thunderid-config.yaml`](https://github.com/thunder-id/samples/blob/main/quickstarts/quickstart-ios/thunderid-config/thunderid-config.yaml)
in the samples repository, alongside the sample it configures. The sign-up flow
registers an additional throwaway user per run, named `e2e_signup_<timestamp>`.

## Things worth knowing

**The application must be `type: mobile` with `attestation.devMode: true`.** A mobile application
normally has to prove its binary identity through platform attestation before it can initiate a
flow directly, and `/flow/execute` rejects it with `FES-1016` otherwise. Apple App Attest does not
exist in the Simulator, so the check can never be satisfied on the device these flows run on.
`devMode` is test-only and must never be enabled on a real tenant.

**`POST /import` silently drops the `attestation` block.** It reports the import as successful and
then stores `attestation: null`, which is why `run-e2e.sh` re-applies it over
`PUT /applications/{id}`. Once the import path preserves it, that step can be removed.

**Sign-up does not sign the user in.** The registration flow completes without issuing an
assertion, so the app returns to the landing screen with the account created but no session. The
sign-up flow therefore signs in afterwards with the credentials it just registered, which is also
what proves the new account actually works.

**Tokens survive `clearState`.** They are stored in the Keychain, which lives outside the app
container and outlives both a state reset and a reinstall. A previous run can leave the app
signed in, so every flow starts with the `ensure-signed-out` subflow rather than assuming a clean
device.

**`change-credential.yaml` actually changes the test user's password.** It gives the current password, changes it to a temporary value, signs in again (the change revokes the user's tokens), and changes it back to `TestPassword@123` before finishing. If a run fails between those two changes, `e2e_mobile_user` is left on the temporary password. Delete the user, or start a fresh server, so provisioning creates it again with `TestPassword@123`.

**`npx thunderid` cannot be used in CI.** It renders an interactive TUI and aborts with
`bubbletea: could not open TTY` whenever stdout is not a terminal. `run-e2e.sh` downloads the
release directly and calls the distribution's own `setup.sh` and `start.sh`, which take the same
arguments non-interactively.
