import Foundation

enum InterfaceLanguage: String, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var pickerTitle: String {
        switch self {
        case .simplifiedChinese: "中文"
        case .english: "English"
        }
    }
}

enum L10n {
    static var currentLanguage: InterfaceLanguage {
        let rawValue = UserDefaults.standard.string(forKey: Defaults.interfaceLanguageKey)
        return InterfaceLanguage(rawValue: rawValue ?? "") ?? .simplifiedChinese
    }

    static func string(
        _ key: String,
        language: InterfaceLanguage? = nil
    ) -> String {
        let selectedLanguage = language ?? currentLanguage
        guard let bundle = bundle(for: selectedLanguage) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(
        _ key: String,
        _ arguments: CVarArg...,
        language: InterfaceLanguage? = nil
    ) -> String {
        let selectedLanguage = language ?? currentLanguage
        return String(
            format: string(key, language: selectedLanguage),
            locale: selectedLanguage.locale,
            arguments: arguments
        )
    }

    private static func bundle(for language: InterfaceLanguage) -> Bundle? {
        if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        #if SWIFT_PACKAGE
        if let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        #endif
        return nil
    }
}
