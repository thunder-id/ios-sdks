// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum ControlKind: Equatable {
    case text
    case bool
    case options([String])
}

struct StoryControl {
    let name: String
    let kind: ControlKind
}

struct Story: Identifiable {
    let id: String
    let name: String
    let preset: [String: String]
}

typealias PropValues = [String: String]

extension PropValues {
    func flag(_ key: String) -> Bool { self[key] == "true" }
    func text(_ key: String) -> String { self[key] ?? "" }
}

/// A ThunderIDSwiftUI component with its stories, editable props and snippet generator.
struct ComponentSpec: Identifiable {
    let id: String
    let name: String
    let group: String
    let defaults: PropValues
    let controls: [StoryControl]
    let stories: [Story]
    /// Flow components render a full form, so the preview gets more room.
    var isTall = false
    let snippet: (PropValues) -> String
}

enum ExplorerCatalog {
    static func components(applicationId: String, ids: AdminStoryIds = AdminStoryIds()) -> [ComponentSpec] {
        actions + user + [languageSwitcher, logo] + flows(applicationId: applicationId) + [guards] + admin(ids: ids)
            + customRender(ids: ids)
    }

    // MARK: - Actions

    private static let variantControl = StoryControl(name: "variant", kind: .options(["connected", "base"]))
    private static let labelControl = StoryControl(name: "label", kind: .text)

    private static let actions: [ComponentSpec] = [
        ComponentSpec(
            id: "signInButton",
            name: "SignInButton",
            group: "Actions",
            defaults: ["variant": "connected", "label": "Sign in", "isLoading": "false"],
            controls: [variantControl, labelControl, StoryControl(name: "isLoading", kind: .bool)],
            stories: [
                Story(id: "connected", name: "Connected", preset: ["variant": "connected", "isLoading": "false"]),
                Story(id: "base", name: "Base", preset: ["variant": "base", "isLoading": "false"]),
                Story(id: "loading", name: "Loading", preset: ["variant": "base", "isLoading": "true"])
            ]
        ) { values in
            values.text("variant") == "connected"
                ? "SignInButton {\n    // start sign-in\n}"
                : "BaseSignInButton(\n    label: \(quote(values.text("label"))),\n"
                    + "    isLoading: \(values.text("isLoading"))\n) {\n    // start sign-in\n}"
        },
        ComponentSpec(
            id: "signOutButton",
            name: "SignOutButton",
            group: "Actions",
            defaults: ["variant": "base", "label": "Sign out", "isLoading": "false"],
            controls: [variantControl, labelControl, StoryControl(name: "isLoading", kind: .bool)],
            stories: [
                Story(id: "base", name: "Base", preset: ["variant": "base", "isLoading": "false"]),
                Story(id: "connected", name: "Connected", preset: ["variant": "connected", "isLoading": "false"]),
                Story(id: "loading", name: "Loading", preset: ["variant": "base", "isLoading": "true"])
            ]
        ) { values in
            values.text("variant") == "connected"
                ? "SignOutButton {\n    // signed out\n}"
                : "BaseSignOutButton(\n    label: \(quote(values.text("label"))),\n"
                    + "    isLoading: \(values.text("isLoading"))\n) {\n    // sign out\n}"
        },
        ComponentSpec(
            id: "signUpButton",
            name: "SignUpButton",
            group: "Actions",
            defaults: ["variant": "connected", "label": "Create account"],
            controls: [variantControl, labelControl],
            stories: [
                Story(id: "connected", name: "Connected", preset: ["variant": "connected"]),
                Story(id: "base", name: "Base", preset: ["variant": "base"])
            ]
        ) { values in
            values.text("variant") == "connected"
                ? "SignUpButton {\n    // start sign-up\n}"
                : "BaseSignUpButton(label: \(quote(values.text("label")))) {\n    // start sign-up\n}"
        }
    ]

    // MARK: - User

    private static let user: [ComponentSpec] = [
        ComponentSpec(
            id: "userAvatar",
            name: "UserAvatar",
            group: "User",
            defaults: ["source": "sample", "name": "Liam Chen", "size": "72"],
            controls: [
                StoryControl(name: "source", kind: .options(["session", "sample", "none"])),
                StoryControl(name: "name", kind: .text),
                StoryControl(name: "size", kind: .options(["32", "48", "72"]))
            ],
            stories: [
                Story(id: "sample", name: "Sample user", preset: ["source": "sample"]),
                Story(id: "session", name: "Signed-in user", preset: ["source": "session"]),
                Story(id: "none", name: "No user", preset: ["source": "none"])
            ]
        ) { values in
            switch values.text("source") {
            case "session":
                return "UserAvatar(size: \(values.text("size")))"
            case "none":
                return "BaseUserAvatar(user: nil, size: \(values.text("size")))"
            default:
                let name = quote(values.text("name"))
                return "BaseUserAvatar(\n    user: User(claims: [\"displayName\": AnyCodable(\(name))]),\n"
                    + "    size: \(values.text("size"))\n)"
            }
        },
        ComponentSpec(
            id: "userDropdown",
            name: "UserDropdown",
            group: "User",
            defaults: [:],
            controls: [],
            stories: [Story(id: "default", name: "Default", preset: [:])]
        ) { _ in
            "UserDropdown(\n    onProfileTap: { /* open profile */ },\n    onSignOutComplete: { /* signed out */ }\n)"
        },
        ComponentSpec(
            id: "userProfile",
            name: "UserProfile",
            group: "User",
            defaults: [:],
            controls: [],
            stories: [Story(id: "default", name: "Default", preset: [:])],
            isTall: true
        ) { _ in
            "UserProfile(\n    onSaved: { /* saved */ },\n    onError: { /* failed */ }\n)"
        },
        ComponentSpec(
            id: "changeCredential",
            name: "ChangeCredential",
            group: "User",
            defaults: ["attribute": "password"],
            controls: [StoryControl(name: "attribute", kind: .text)],
            stories: [Story(id: "password", name: "Password", preset: ["attribute": "password"])],
            isTall: true
        ) { values in
            "ChangeCredential(attribute: \(quote(values.text("attribute")))) {\n    // updated\n}"
        },
        ComponentSpec(
            id: "verifyAttribute",
            name: "VerifyAttribute",
            group: "User",
            defaults: ["attribute": "email", "flowHandle": defaultVerificationHandle],
            controls: [
                StoryControl(name: "attribute", kind: .text),
                StoryControl(name: "flowHandle", kind: .text)
            ],
            stories: [
                Story(id: "email", name: "Email", preset: ["attribute": "email"]),
                Story(id: "mobile", name: "Mobile number", preset: ["attribute": "mobile_number"])
            ],
            isTall: true
        ) { values in
            "VerifyAttribute(\n    attribute: \(quote(values.text("attribute"))),\n"
                + "    flowHandle: \(quote(values.text("flowHandle"))),\n"
                + "    onComplete: { /* verified */ },\n    onCancel: { /* close */ }\n)"
                + "\n.id(\(quote(values.text("attribute"))))"
        }
    ]

    /// The server's shipped self attribute verification flow.
    private static let defaultVerificationHandle = "default-self-attribute-verification-flow"

    // MARK: - Presentation and branding

    private static let languageSwitcher = ComponentSpec(
        id: "languageSwitcher",
        name: "LanguageSwitcher",
        group: "Presentation",
        defaults: ["locales": "en-US, fr-FR, si-LK"],
        controls: [StoryControl(name: "locales", kind: .text)],
        stories: [
            Story(id: "three", name: "Three locales", preset: ["locales": "en-US, fr-FR, si-LK"]),
            Story(id: "default", name: "Default", preset: ["locales": ""])
        ]
    ) { values in
        let locales = localeList(values.text("locales")).map(quote).joined(separator: ", ")
        return locales.isEmpty ? "LanguageSwitcher()" : "LanguageSwitcher(locales: [\(locales)])"
    }

    private static let initialsSpec = "avatar:shape=circle,variant=two_letter,content=TI,colors=2"
    private static let animalSpec = "avatar:shape=rounded,variant=anonymous_animal,content=otter"

    private static let logo = ComponentSpec(
        id: "logoView",
        name: "LogoView",
        group: "Branding",
        defaults: ["spec": initialsSpec, "fallbackSeedText": "ThunderID"],
        controls: [StoryControl(name: "spec", kind: .text), StoryControl(name: "fallbackSeedText", kind: .text)],
        stories: [
            Story(id: "initials", name: "Initials", preset: ["spec": initialsSpec]),
            Story(id: "animal", name: "Animal", preset: ["spec": animalSpec]),
            Story(id: "entity", name: "Entity", preset: ["spec": "avatar:variant=anonymous_entity,content=lighthouse"]),
            Story(id: "emoji", name: "Emoji", preset: ["spec": "emoji:🛡️"])
        ]
    ) { values in
        "LogoView(\n    spec: \(quote(values.text("spec"))),\n"
            + "    fallbackSeedText: \(quote(values.text("fallbackSeedText")))\n)"
            + "\n.frame(width: 72, height: 72)"
    }

    // MARK: - Flows and guards

    private static func flows(applicationId: String) -> [ComponentSpec] {
        [
            ComponentSpec(
                id: "signIn",
                name: "SignIn",
                group: "Flows",
                defaults: ["applicationId": applicationId],
                controls: [StoryControl(name: "applicationId", kind: .text)],
                stories: [Story(id: "default", name: "App-native", preset: [:])],
                isTall: true
            ) { values in
                "SignIn(\n    applicationId: \(quote(values.text("applicationId"))),\n"
                    + "    onComplete: { /* signed in */ },\n    onError: { message in print(message) }\n)"
            },
            ComponentSpec(
                id: "signUp",
                name: "SignUp",
                group: "Flows",
                defaults: ["applicationId": applicationId],
                controls: [StoryControl(name: "applicationId", kind: .text)],
                stories: [Story(id: "default", name: "App-native", preset: [:])],
                isTall: true
            ) { values in
                "SignUp(\n    applicationId: \(quote(values.text("applicationId"))),\n"
                    + "    onComplete: { /* account created */ },\n    onError: { message in print(message) }\n)"
            }
        ]
    }

    private static let guards = ComponentSpec(
        id: "guards",
        name: "SignedIn / SignedOut",
        group: "Guards",
        defaults: ["guard": "SignedIn", "content": "Welcome back", "fallback": "Please sign in"],
        controls: [
            StoryControl(name: "guard", kind: .options(["SignedIn", "SignedOut"])),
            StoryControl(name: "content", kind: .text),
            StoryControl(name: "fallback", kind: .text)
        ],
        stories: [
            Story(id: "signedIn", name: "SignedIn", preset: ["guard": "SignedIn"]),
            Story(id: "signedOut", name: "SignedOut", preset: ["guard": "SignedOut"])
        ]
    ) { values in
        "\(values.text("guard")) {\n    Text(\(quote(values.text("content"))))\n} fallback: {\n"
            + "    Text(\(quote(values.text("fallback"))))\n}"
    }

    // MARK: - Helpers

    static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func localeList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
