import SwiftUI

/// Entries and screens share brand colors; icons and interaction details follow iOS conventions.
/// 入口与页面共用品牌色，图标与交互细节遵循 iOS 习惯。
enum DemoTheme {
    // Home follows the public Android palette; content screens keep their own colors.
    static let homeBackground = Color(red: 2 / 255, green: 63 / 255, blue: 66 / 255)
    static let homeText = Color.white
    static let homeSecondaryText = Color.white.opacity(191 / 255)
    static let homeSurface = Color.white.opacity(38 / 255)
    static let homeBorder = Color.white.opacity(61 / 255)
    static let homeArrowSurface = Color.white.opacity(20 / 255)
    static let homeArrow = Color.white.opacity(0.6)
    static let home = Color(red: 60 / 255, green: 7 / 255, blue: 64 / 255)
    static let primary = Color(red: 103 / 255, green: 173 / 255, blue: 91 / 255)
    static let content = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let contentAccent = Color(red: 7 / 255, green: 122 / 255, blue: 99 / 255)
    static let search = Color(red: 12 / 255, green: 19 / 255, blue: 32 / 255)
    static let searchSurface = Color(red: 23 / 255, green: 34 / 255, blue: 51 / 255)
    static let searchAccent = Color(red: 121 / 255, green: 227 / 255, blue: 192 / 255)
}
