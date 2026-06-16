import Foundation

/// Resolves localized strings for ThunderSwiftUI components (spec §8.1 i18n).
///
/// Resolution order: custom bundle for active locale → custom bundle for fallback locale → English defaults.
public final class ThunderI18n: ObservableObject {
    @Published public private(set) var activeLocale: String

    private let bundles: [String: [String: String]]
    private let fallbackLocale: String
    private let storageKey: String

    public init(
        bundles: [String: [String: String]] = [:],
        language: String? = nil,
        fallbackLanguage: String = "en-US",
        storageKey: String = "thunder_locale"
    ) {
        self.bundles = bundles
        self.fallbackLocale = fallbackLanguage
        self.storageKey = storageKey
        let stored = UserDefaults.standard.string(forKey: storageKey)
        self.activeLocale = language ?? stored ?? fallbackLanguage
    }

    /// Returns the localized string for `key`, falling back through the chain.
    public func resolve(_ key: String) -> String {
        bundles[activeLocale]?[key]
            ?? bundles[fallbackLocale]?[key]
            ?? DefaultStrings.all[key]
            ?? key
    }

    /// Sets the active locale and persists it to UserDefaults.
    public func setLocale(_ locale: String) {
        guard locale != activeLocale else { return }
        UserDefaults.standard.set(locale, forKey: storageKey)
        activeLocale = locale
    }
}
