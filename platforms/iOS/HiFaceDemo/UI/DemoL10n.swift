import Foundation

/// Demo 按系统地区选语言，不改变 SDK 的错误、日志或特征格式。
enum DemoL10n {
    static func language(for region: String?) -> String {
        switch region?.uppercased() {
        case "CN", "HK", "MO", "TW": "zh-Hans"
        default: "en"
        }
    }

    static var systemRegion: String? {
        if #available(iOS 16, macOS 13, *) { return Locale.current.region?.identifier }
        return Locale.current.regionCode
    }

    static var locale: Locale { Locale(identifier: language(for: systemRegion)) }

    private static let bundledLanguages: [String: Bundle] = {
        var bundles: [String: Bundle] = [:]
        for language in ["en", "zh-Hans"] {
            if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
               let bundle = Bundle(path: path) { bundles[language] = bundle }
        }
        return bundles
    }()

    static func text(_ key: String, _ arguments: [String] = [],
                     region: String? = systemRegion, bundle: Bundle = .main) -> String {
        let language = language(for: region)
        let localizedBundle: Bundle
        if bundle === Bundle.main {
            localizedBundle = bundledLanguages[language] ?? bundledLanguages["en"] ?? bundle
        } else {
            let path = bundle.path(forResource: language, ofType: "lproj")
                ?? bundle.path(forResource: "en", ofType: "lproj")
            localizedBundle = path.flatMap(Bundle.init(path:)) ?? bundle
        }
        let format = localizedBundle.localizedString(forKey: key, value: nil, table: "Localizable")
        // 一次替换，防止用户输入的 {0} 等文本再次被当成格式占位符。
        var result = ""
        var remainder = format[...]
        while let open = remainder.firstIndex(of: "{"), let close = remainder[open...].firstIndex(of: "}") {
            result += remainder[..<open]
            let placeholder = remainder[remainder.index(after: open)..<close]
            if let index = Int(placeholder), arguments.indices.contains(index) { result += arguments[index] }
            else { result += remainder[open...close] }
            remainder = remainder[remainder.index(after: close)...]
        }
        return result + remainder
    }
}
