import XCTest
@testable import ThunderSwiftUI

final class ComponentTests: XCTestCase {

    // MARK: - ThunderI18n

    func testI18nResolvesDefaultString() {
        let i18n = ThunderI18n()
        XCTAssertEqual(i18n.resolve("signIn.button"), "Sign in")
    }

    func testI18nResolvesCustomBundle() {
        let i18n = ThunderI18n(bundles: ["en-US": ["signIn.button": "Log in"]])
        XCTAssertEqual(i18n.resolve("signIn.button"), "Log in")
    }

    func testI18nFallsBackToDefaultForMissingKey() {
        let i18n = ThunderI18n(bundles: ["en-US": [:]])
        XCTAssertEqual(i18n.resolve("signOut.button"), "Sign out")
    }

    func testI18nSetsLocale() {
        let i18n = ThunderI18n(
            bundles: ["fr-FR": ["signIn.button": "Se connecter"]],
            language: "en-US"
        )
        i18n.setLocale("fr-FR")
        XCTAssertEqual(i18n.activeLocale, "fr-FR")
        XCTAssertEqual(i18n.resolve("signIn.button"), "Se connecter")
    }

    func testI18nFallsBackThroughFallbackLocale() {
        let i18n = ThunderI18n(
            bundles: ["es-ES": ["signIn.button": "Iniciar sesión"]],
            language: "de-DE",
            fallbackLanguage: "es-ES"
        )
        XCTAssertEqual(i18n.resolve("signIn.button"), "Iniciar sesión")
    }

    func testI18nReturnsKeyForUnknown() {
        let i18n = ThunderI18n()
        XCTAssertEqual(i18n.resolve("not.a.real.key"), "not.a.real.key")
    }

    // MARK: - DefaultStrings

    func testDefaultStringsContainsAllExpectedKeys() {
        let requiredKeys = [
            "signIn.button", "signOut.button", "signUp.button",
            "userProfile.title", "userProfile.save",
            "languageSwitcher.title",
        ]
        for key in requiredKeys {
            XCTAssertNotNil(DefaultStrings.all[key], "Missing default string for key: \(key)")
        }
    }
}
