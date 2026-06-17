import SwiftUI

/// Locale picker that updates active language for component labels (spec §8.4 Presentation).
public struct LanguageSwitcher: View {
    @EnvironmentObject private var i18n: ThunderI18n
    public let locales: [String]

    public init(locales: [String] = []) { self.locales = locales }

    public var body: some View {
        BaseLanguageSwitcher(locales: locales) { available, active, select in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(available, id: \.self) { locale in
                    Button {
                        select(locale)
                    } label: {
                        HStack {
                            Text(locale)
                            if locale == active {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .accessibilityLabel(locale)
                    .accessibilityAddTraits(locale == active ? .isSelected : [])
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }
}

/// Unstyled base variant (spec §8.3).
public struct BaseLanguageSwitcher<Content: View>: View {
    @EnvironmentObject private var state: ThunderState
    @EnvironmentObject private var i18n: ThunderI18n
    public let locales: [String]
    public let content: ([String], String, @escaping (String) -> Void) -> Content

    public init(
        locales: [String] = [],
        @ViewBuilder content: @escaping ([String], String, @escaping (String) -> Void) -> Content
    ) {
        self.locales = locales
        self.content = content
    }

    public var body: some View {
        content(locales.isEmpty ? ["en-US"] : locales, i18n.activeLocale) { locale in
            state.setLocale(locale)
        }
    }
}
