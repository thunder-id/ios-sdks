# ThunderID iOS SDKs — Agent Instructions

## Project overview

Swift package providing the ThunderID authentication SDK (`ThunderID`) and a SwiftUI component library (`ThunderIDSwiftUI`). The Quickstart demo app lives in the samples repository at [`quickstarts/ios`](https://github.com/thunder-id/samples/tree/main/quickstarts/ios); the E2E suite fetches it and builds it against this checkout via `Tests/e2e/scripts/prepare-sample.sh`.

The [`Playground/`](Playground) app exercises every SDK capability (capability checks, a component explorer, a session inspector and an event log) against the SDK sources in this checkout through a local package reference. See [Playground/README.md](Playground/README.md) to run it against a local ThunderID server. When you add or change a capability or a ThunderIDSwiftUI component, add or update its check or story there too.

## SDK development specification

Every change to this SDK goes through the ThunderID SDK development specification. It is
maintained in the product repository and governs all four SDK repositories, so it is linked
here rather than copied.

- [SDK development specification](https://github.com/thunder-id/thunderid/blob/main/docs-internals/sdk-development/spec.md):
  the contract this SDK implements. Layering, operational modes, configuration keys, client
  surface, error model, security floor, platform packaging, testing, and the cross-SDK parity
  rules.
- [SDK threat model](https://github.com/thunder-id/thunderid/blob/main/docs-internals/sdk-development/threat-model.md):
  the security posture the specification's floor comes from.
- [`sdk-development` skill](https://github.com/thunder-id/thunderid/blob/main/.agent/skills/sdk-development/SKILL.md):
  loads both documents and drives the work, from locating the SDK checkouts through validation
  to raising the linked pull requests.

Read the specification before adding or changing an operation, configuration key, error, or UI
component. A capability that lands here usually needs to land in the sibling SDKs too, and the
pull request has to answer that question either way, by linking the sibling pull requests or
by saying why they are not needed.

## Vendor naming rules

The SDK is white-labelable: a consuming app can override the brand/vendor namespace via `ThunderIDConfig.vendor`, so storage keys, log tags, and similar runtime names shouldn't be pinned to one brand.

- Do not hardcode the literal `thunderid`/`ThunderID`/`THUNDERID` (any casing) when building a runtime key/name that a consumer's `vendor` override should control — Keychain service names, log tags, and the like.
- It's fine for the **entry point** — the module name or a type whose purpose IS to represent the SDK itself (e.g. `ThunderIDClient`, `ThunderIDProvider`) — to carry the name. That's a fixed identity, not a per-tenant value. Don't flag those.
- Avoiding the vendor name entirely is the best outcome, when the brand prefix isn't actually load-bearing.
- When a brand-scoped namespace is genuinely required, resolve it from `config.vendor` (which already defaults to `"thunderid"`) instead of hardcoding a literal. If the same default-resolution logic starts appearing in more than one place, extract a small shared helper rather than repeating the literal default.

## Build & test

```bash
# Build and run tests
swift test

# Run SwiftLint (must pass before any PR); this covers Playground/ too
swiftlint lint --strict

# Build the playground against the local SDK (CI runs this in the build-playground job)
(cd Playground && swift build)
```

## SwiftLint compliance (required)

All code **must pass `swiftlint lint --strict` with zero violations**. The CI `lint` job runs this check on every PR and treats any violation as a build failure.

Configuration lives in [.swiftlint.yml](.swiftlint.yml). Key rules enforced:

| Rule | What to do |
|---|---|
| `line_length` | Keep lines ≤ 120 characters. Wrap long function signatures and call-sites across multiple lines. |
| `trailing_comma` | No trailing comma on the last element of a collection literal or argument list. |
| `sorted_imports` | Sort `import` statements alphabetically (`CryptoKit` before `Foundation`). |
| `statement_position` | `else`/`catch` must start on the same line as the closing `}` of the preceding block — use `} else {` style. |
| `trailing_closure` | Use trailing closure syntax whenever the last parameter is a closure: `Foo { }` not `Foo(bar: { })`. |
| `multiline_function_chains` | In a multi-line chain, each call must be on its own line — don't combine `.font(.title2).bold()` on one line. |
| `identifier_name` | Variable names must be 3–40 characters. Avoid single-letter loop variables like `i`; use `idx` or a descriptive name. |
| `cyclomatic_complexity` | Functions must have complexity ≤ 10. Extract branches into private helper methods. |
| `for_where` | Prefer `for x in collection where condition` over `for x in collection { if condition { ... } }`. |
| `file_length` | Files should be ≤ 500 lines. Split large files by extracting types into a companion file (e.g. `FooComponents.swift`). |
| `type_body_length` | Class/struct bodies should be ≤ 350 lines. Move private helpers to a `private extension`. |
| `trailing_newline` | Every file must end with exactly one newline character. |

### Practical checklist before finishing any change

1. Run `swiftlint lint --strict` locally and fix every reported violation.
2. Never use single-letter loop variables (`i`, `j`). Use `idx`, `row`, or a meaningful name.
3. Wrap any function signature or call longer than 120 chars across multiple lines with one parameter per line.
4. Put `else`/`else if` on the same line as the closing `}`: `} else {`.
5. When adding imports, keep them sorted alphabetically.
6. If a new file grows past ~450 lines, split it proactively.

## File layout

```
Sources/ThunderID/          Core SDK
  api/account/              The signed-in user's own account (/users/me)
  api/auth/                 Sign-in: flow execution, PKCE, federated and passkey sessions
  api/management/           Management operations and administration flows
  backend/, http/, token/   Backend mode, transport and token storage
Sources/ThunderIDSwiftUI/   SwiftUI component library
  components/auth/          Sign-in/sign-up flows and DeviceGrant, plus buttons/ (incl. adapters/), flow/ and guards/
  components/account/       The signed-in user's own account (User, UserProfile, ChangeCredential, ...)
  components/management/    Management screens (agents/, applications/, groups/, organization-units/,
                            projects/, roles/, sharing/, users/, shared/)
  components/common/        Shared pieces used across groups (branding/, LanguageSwitcher)
Tests/                      Unit tests (excluded from SwiftLint); component tests mirror components/
                            under Tests/ThunderIDSwiftUITests/components/
Playground/                 SwiftUI playground app built against the local SDK
.swiftlint.yml              Lint configuration
.github/workflows/          CI pipelines
```

## Adding or changing a component

The [SDK development specification](https://github.com/thunder-id/thunderid/blob/main/docs-internals/sdk-development/spec.md) (UI) is the contract. In practice, every component:

1. **Lives in its functional group:** `auth/` (sign-in, sign-up, recovery, invites, callback, with `buttons/`, `flow/` and `guards/` inside), `account/` (the signed-in user's own data), `management/` (users, groups, roles, agents, applications), or `common/` (shared across groups, such as the language switcher and branding). Primitives and the data layer keep their own folders.
2. **Ships a styled variant and a `Base` variant.** `Base` takes its data and callbacks as parameters, with no SDK state, so an app can drive it itself (e.g. `BaseUserList`).
3. **Accepts a custom render on both variants.** Passing it replaces the built-in UI, while the component keeps its data loading, state and actions. The mechanism is the platform's own:
   - SwiftUI: an optional `content` closure, the same pattern as `BaseSignIn`.
   It receives everything needed to draw the component: rows, columns, paging (`limit`, `offset`, `totalResults`, page change) and selection for a list; values, setters, submit and validity for a form; the record and the actions the app has allowed for a details, members, assignments or permissions view; plus loading and error state. Behaviour the specification requires still holds under a custom render: data-changing actions are off unless the app turns them on, a delete asks for confirmation, and server errors appear as translated messages.
4. **Takes every string from the translation bundle**, in every shipped locale.
5. **Tags elements rendered from a server-described flow step** with `thunderid-field-<id>` and `thunderid-action-<ref>`.
6. **Has tests** for the built-in UI and for a custom render (XCTest).
7. **Has a playground story,** including a **Custom rendering** variant drawn with the platform's own UI toolkit, and a capability check if it calls the server.

A component that changes here usually needs the same change in the sibling SDKs. See the parity rules in the specification.

## Samples

The quickstarts and integration samples live in [thunder-id/samples](https://github.com/thunder-id/samples), and each one pins a released version of this SDK. A change here therefore can't break a sample until the sample bumps its version, which is exactly when a break would surface for a real app. Before raising a pull request, check every sample that uses this SDK:

- **A sample stops compiling or behaving the same** (a renamed type or package, a changed signature, a moved default): raise a samples pull request that bumps the SDK version and fixes the sample. Keep it as a draft until the SDK release it needs is out.
- **The change adds something a sample exists to show** (a self-care capability for `self-care/account`, a management component or operation for `management/admin`, a new sign-in option for the quickstarts): update that sample in the same samples pull request, so it demonstrates the new capability rather than working around its absence.
- Link the samples pull request from this pull request's **Related PRs**, or say why no sample is affected.

## Code style

- Swift 5.9+, minimum deployment iOS 16 / macOS 13.
- No third-party dependencies in `Sources/` — only `Foundation`, `CryptoKit`, `SwiftUI`.
- Use `async/throws` over completion handlers.
- Mark internal helpers `private`; expose only intentional API as `public`.
