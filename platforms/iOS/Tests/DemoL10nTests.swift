import Foundation

@main struct DemoL10nTests {
    static func main() {
        for region in ["CN", "HK", "MO", "TW", "cn", "hk"] {
            precondition(DemoL10n.language(for: region) == "zh-Hans")
            precondition(DemoL10n.text("任务正在执行", region: region) == "任务正在执行")
        }
        for region in ["US", "GB", "SG", "MY", "JP", "", nil] {
            precondition(DemoL10n.language(for: region) == "en")
            precondition(DemoL10n.text("任务正在执行", region: region) == "Import in progress")
        }
        precondition(DemoL10n.text("{0}：已保存 {1} 条，失败 {2} 条", ["Stopped", "37", "2"], region: "US") == "Stopped: saved 37, failed 2")
        precondition(DemoL10n.text("{0}：已保存 {1} 条，失败 {2} 条", ["{1}", "37", "2"], region: "US") == "{1}: saved 37, failed 2")
        print("Demo localization: region policy, native resources and safe interpolation passed")
    }
}
