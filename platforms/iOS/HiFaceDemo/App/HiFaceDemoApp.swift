import Foundation
import HiFace
import SwiftUI

enum DemoEnvironment {
    static func makeSDK() -> HiFaceSDK {
        // 二进制 SDK 自带模型；显式指定 App Bundle 会覆盖 SDK 的 Framework 资源定位。
        HiFaceSDK()
    }
}

@main
struct HiFaceDemoApp: App {
    var body: some Scene {
        WindowGroup { DemoHomeView().environment(\.locale, DemoL10n.locale) }
    }
}
