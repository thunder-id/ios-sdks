// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ThunderIDSwiftUI

/// Covers the shipped locales: every key in every locale, the placeholders kept, and the order the
/// strings resolve in.
final class TranslationsTests: XCTestCase {
    private let storageKey = "translations_tests_locale"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        super.tearDown()
    }

    private func placeholders(_ text: String) -> Set<String> {
        let regex = try? NSRegularExpression(pattern: "\\{[A-Za-z]+\\}")
        let range = NSRange(text.startIndex..., in: text)
        let found = regex?.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        // A credential template may use either form; both are substituted.
        return Set((found ?? []).map { $0 == "{credentialLower}" ? "{credential}" : $0 })
    }

    func testShipsTheSameLocalesAsTheJavaScriptSDK() {
        XCTAssertEqual(
            DefaultStrings.locales,
            ["en-US", "fr-FR", "hi-IN", "ja-JP", "pt-BR", "pt-PT", "si-LK", "ta-IN", "te-IN"]
        )
    }

    func testEveryLocaleHasEveryKeyWithItsPlaceholders() throws {
        for locale in DefaultStrings.locales {
            let strings = try XCTUnwrap(DefaultStrings.strings(for: locale), locale)
            XCTAssertEqual(Set(strings.keys), Set(DefaultStrings.all.keys), "\(locale) keys differ")
            for (key, english) in DefaultStrings.all {
                let translated = try XCTUnwrap(strings[key])
                XCTAssertFalse(translated.isEmpty, "\(locale) \(key) is empty")
                XCTAssertEqual(placeholders(translated), placeholders(english), "\(locale) \(key) placeholders")
            }
        }
    }

    func testTranslationsMatchTheJavaScriptSDK() {
        XCTAssertEqual(DefaultStrings.strings(for: "fr-FR")?["admin.common.actions.remove"], "Retirer")
        XCTAssertEqual(DefaultStrings.strings(for: "ja-JP")?["admin.roles.permissions.title"], "権限")
        XCTAssertEqual(DefaultStrings.strings(for: "pt-PT")?["signIn.button"], "Iniciar Sessão")
    }

    func testLocalesMatchByLanguageWhenNotShippedExactly() {
        XCTAssertEqual(DefaultStrings.strings(for: "fr")?["signOut.button"], "Se déconnecter")
        XCTAssertEqual(DefaultStrings.strings(for: "pt_PT")?["signIn.button"], "Iniciar Sessão")
        XCTAssertEqual(DefaultStrings.strings(for: "pt-AO")?["signIn.button"], "Entrar")
        XCTAssertNil(DefaultStrings.strings(for: "de-DE"))
    }

    func testResolvesCustomThenShippedThenFallback() {
        let i18n = ThunderIDI18n(
            bundles: ["fr-FR": ["signIn.button": "Connexion"], "en-US": ["signOut.button": "Log out"]],
            language: "fr-FR",
            storageKey: storageKey
        )
        XCTAssertEqual(i18n.resolve("signIn.button"), "Connexion", "The app's own bundle wins")
        XCTAssertEqual(i18n.resolve("signOut.button"), "Se déconnecter", "Shipped strings for the active locale")
        XCTAssertEqual(i18n.resolve("admin.roles.permissions.add"), "Ajouter une autorisation")

        i18n.setLocale("de-DE")
        XCTAssertEqual(i18n.resolve("signOut.button"), "Log out", "The app's fallback bundle")
        XCTAssertEqual(i18n.resolve("signIn.button"), "Sign in", "English defaults last")
        XCTAssertEqual(i18n.resolve("no.such.key"), "no.such.key")
    }
}
