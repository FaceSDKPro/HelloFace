import Foundation

/// 不依赖真机的格式选择回归测试。编译时同时传入 CameraResolutionPolicy.swift。
@main
struct CameraResolutionPolicyTests {
    static func main() {
        let limit = CameraFrameSize(width: 1920, height: 1080)
        func option(_ width: Int, _ height: Int, fov: Float = 60) -> CameraFormatOption {
            CameraFormatOption(size: CameraFrameSize(width: width, height: height), fieldOfView: fov)
        }
        func select(_ formats: [CameraFormatOption], _ tier: CameraAnalysisResolution) -> Int? {
            CameraResolutionPolicy.selectIndex(from: formats, tier: tier, sdkLimit: limit)
        }

        let typical = [option(3840, 2160), option(1920, 1080), option(640, 480), option(1280, 720)]
        precondition(select(typical, .low) == 2)
        precondition(select(typical, .medium) == 3)
        precondition(select(typical, .high) == 1)
        precondition(select([], .high) == nil)
        precondition(select([option(3840, 2160), option(1440, 1440)], .high) == nil)
        precondition(select([option(1920, 1080), option(1280, 720)], .low) == 1)
        precondition(select([option(640, 480), option(960, 540)], .medium) == 1)
        precondition(select([option(640, 480)], .high) == 0)
        precondition(select([option(1080, 1920)], .high) == 0)
        precondition(select([option(1920, 1081), option(0, 480), option(641, 480)], .high) == nil)
        precondition(select([option(1280, 720, fov: 50), option(1280, 720, fov: 65)], .medium) == 1)
        precondition(select([option(1280, 720), option(1280, 720)], .medium) == 0)

        // Mac 固定 30 FPS 摄像头能用于普通页面，也必须能用于 15/5 FPS 搜索分析。
        func captureOption(_ width: Int, _ height: Int, minimum: Double, maximum: Double) -> CameraFormatOption {
            CameraFormatOption(
                size: CameraFrameSize(width: width, height: height),
                fieldOfView: 60,
                frameRateRanges: [CameraFrameRateRange(minimum: minimum, maximum: maximum)]
            )
        }
        func searchSelect(_ formats: [CameraFormatOption]) -> Int? {
            CameraResolutionPolicy.selectIndex(
                from: formats, tier: .low, sdkLimit: limit, preferredFrameRates: [15, 5]
            )
        }
        let fixed30 = captureOption(1280, 720, minimum: 30, maximum: 30)
        func rate(_ target: Double, _ values: [(Double, Double)]) -> Double? {
            CameraFrameRatePolicy.select(target: target, ranges: values.map {
                CameraFrameRateRange(minimum: $0.0, maximum: $0.1)
            })?.framesPerSecond
        }
        precondition(rate(5, [(5, 30)]) == 5)
        precondition(rate(15, [(5, 30)]) == 15)
        precondition(rate(5, [(30, 30), (10, 10), (15, 15)]) == 10)
        precondition(rate(15, [(30, 30), (10, 10), (15, 15)]) == 15)
        precondition(rate(5, [(30, 30)]) == 30)
        precondition(rate(15, [(10, 10), (30, 30)]) == 30)
        precondition(rate(15, [(5, 5), (10, 10)]) == 10)
        precondition(rate(5, [(7.5, 30), (10, 30)]) == 10)
        precondition(rate(5, [(7.5, 9)]) == 9)
        precondition(rate(5, [(12, 30)]) == 15)
        precondition(rate(5, [(7.5, 7.5)]) == 7.5)
        precondition(rate(5, []) == nil)
        precondition(rate(5, [(0, 0), (30, 15), (.nan, 30), (1, .infinity)]) == nil)
        precondition(rate(0, [(5, 30)]) == nil && rate(.nan, [(5, 30)]) == nil)
        precondition(CameraFrameRatePolicy.select(target: 5, ranges: [
            CameraFrameRateRange(minimum: 0, maximum: 0),
            CameraFrameRateRange(minimum: 10, maximum: 15)
        ])?.rangeIndex == 1)
        precondition(searchSelect([fixed30]) == 0)
        precondition(fixed30.supportsFrameRate(30))
        precondition(!fixed30.supportsFrameRate(15))
        precondition(!fixed30.supportsFrameRate(5))
        let activeOnly = captureOption(1280, 720, minimum: 15, maximum: 30)
        let variable = captureOption(1280, 720, minimum: 5, maximum: 30)
        precondition(searchSelect([fixed30, activeOnly, variable]) == 2)
        precondition(searchSelect([fixed30, activeOnly]) == 1)
        precondition(searchSelect([activeOnly]) == 0)
        // 帧率回退不能放宽 SDK 的尺寸或 NV12 偶数尺寸约束。
        precondition(searchSelect([captureOption(3840, 2160, minimum: 5, maximum: 30), fixed30]) == 1)
        precondition(searchSelect([captureOption(3840, 2160, minimum: 30, maximum: 30)]) == nil)
        precondition(searchSelect([captureOption(641, 480, minimum: 30, maximum: 30)]) == nil)
        precondition(CameraAnalysisResolution(storedValue: "standard") == .medium)
        precondition(CameraAnalysisResolution(storedValue: nil) == .medium)
        precondition(CameraAnalysisResolution(storedValue: "corrupt") == .medium)
        precondition(CameraAnalysisResolution(storedValue: nil, fallback: .low) == .low)
        precondition(CameraAnalysisResolution(storedValue: "corrupt", fallback: .low) == .low)
        precondition(CameraAnalysisResolution(storedValue: "high", fallback: .low) == .high)
        for tier in CameraAnalysisResolution.allCases {
            precondition(CameraAnalysisResolution(storedValue: tier.rawValue) == tier)
        }
        // 普通广角镜头最低只能 1.0x；系统提供 0.5 显示倍率的虚拟镜头可准确得到 0.8x。
        precondition(CameraZoomPolicy.deviceFactor(displayMultiplier: 1, minimum: 1, maximum: 8) == 1)
        precondition(CameraZoomPolicy.deviceFactor(displayMultiplier: 0.5, minimum: 1, maximum: 8) == 1.6)
        precondition(CameraZoomPolicy.displayFactor(deviceFactor: 1.6, displayMultiplier: 0.5) == 0.8)
        precondition(CameraZoomPolicy.deviceFactor(displayMultiplier: 0.5, minimum: 2, maximum: 8) == 2)

        // 不同镜头的任意格式组合、横竖方向和 SDK 上限下均不得选到越界或奇数尺寸。
        let inventory = typical + [option(720, 1280), option(960, 540), option(1440, 1440), option(641, 480)]
        var combinations = 0
        for mask in 0..<(1 << inventory.count) {
            let formats = inventory.indices.filter { mask & (1 << $0) != 0 }.map { inventory[$0] }
            for tier in CameraAnalysisResolution.allCases {
                for sdkLimit in [limit, CameraFrameSize(width: 1280, height: 720)] {
                    let chosen = CameraResolutionPolicy.selectIndex(from: formats, tier: tier, sdkLimit: sdkLimit)
                    if let chosen {
                        precondition(formats[chosen].size.fits(within: sdkLimit))
                        let withinBudget = formats.filter {
                            $0.size.fits(within: sdkLimit) && $0.size.fits(within: tier.preferredSize)
                        }
                        if !withinBudget.isEmpty {
                            precondition(formats[chosen].size.fits(within: tier.preferredSize))
                            precondition(formats[chosen].size.pixelCount == withinBudget.map(\.size.pixelCount).max())
                        }
                    } else {
                        precondition(!formats.contains { $0.size.fits(within: sdkLimit) })
                    }
                    combinations += 1
                }
            }
        }
        print("Camera resolution/frame-rate/zoom policy: targeted checks and \(combinations) format combinations passed")
    }
}
