import Foundation

/// 面向人脸分析的画质档位；尺寸是选型预算，不要求镜头提供完全相同的格式。
enum CameraAnalysisResolution: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    init(storedValue: String?, fallback: CameraAnalysisResolution = .medium) {
        self = Self(rawValue: storedValue ?? "") ?? fallback
    }

    var title: String {
        switch self {
        case .low: DemoL10n.text("低")
        case .medium: DemoL10n.text("中")
        case .high: DemoL10n.text("高")
        }
    }

    var detail: String {
        switch self {
        case .low: DemoL10n.text("约 640 × 480 · 性能优先")
        case .medium: DemoL10n.text("约 1280 × 720 · 兼顾清晰度与性能")
        case .high: DemoL10n.text("约 1920 × 1080 · 细节更多，耗电更高")
        }
    }

    var preferredSize: CameraFrameSize {
        switch self {
        case .low: CameraFrameSize(width: 640, height: 480)
        case .medium: CameraFrameSize(width: 1280, height: 720)
        case .high: CameraFrameSize(width: 1920, height: 1080)
        }
    }
}

struct CameraFrameSize: Equatable, Sendable {
    let width: Int
    let height: Int

    var longSide: Int { max(width, height) }
    var shortSide: Int { min(width, height) }
    var pixelCount: Int { width * height }

    func fits(within limit: CameraFrameSize) -> Bool {
        width > 0 && height > 0 && width.isMultiple(of: 2) && height.isMultiple(of: 2)
            && longSide <= limit.longSide && shortSide <= limit.shortSide
    }
}

struct CameraFrameRateRange: Sendable {
    let minimum: Double
    let maximum: Double

    func contains(_ framesPerSecond: Double) -> Bool {
        minimum <= framesPerSecond && framesPerSecond <= maximum
    }
}

enum CameraFrameRatePolicy {
    struct Selection: Equatable {
        let rangeIndex: Int
        let framesPerSecond: Double
    }

    /// 保持支持的目标帧率；回退优先选最低的目标整倍数，避免 7.5/5 等相位导致多丢帧。
    static func select(target: Double, ranges: [CameraFrameRateRange]) -> Selection? {
        guard target.isFinite, target > 0 else { return nil }
        var aligned: Selection?, above: Selection?, below: Selection?
        for (index, range) in ranges.enumerated() {
            guard range.minimum.isFinite, range.maximum.isFinite,
                  range.minimum > 0, range.maximum >= range.minimum else { continue }
            if range.contains(target) { return Selection(rangeIndex: index, framesPerSecond: target) }
            if range.minimum > target {
                let multiple = ceil(range.minimum / target) * target
                if range.contains(multiple), aligned == nil || multiple < aligned!.framesPerSecond {
                    aligned = Selection(rangeIndex: index, framesPerSecond: multiple)
                }
                // 没有可用整倍数时保留该范围上限，不能为了少采集而进一步恶化探测间隔。
                if above == nil || range.maximum < above!.framesPerSecond {
                    above = Selection(rangeIndex: index, framesPerSecond: range.maximum)
                }
            }
            if range.maximum < target, below == nil || range.maximum > below!.framesPerSecond {
                below = Selection(rangeIndex: index, framesPerSecond: range.maximum)
            }
        }
        return aligned ?? above ?? below
    }
}

struct CameraFormatOption: Sendable {
    let size: CameraFrameSize
    let fieldOfView: Float
    let frameRateRanges: [CameraFrameRateRange]

    init(
        size: CameraFrameSize,
        fieldOfView: Float,
        frameRateRanges: [CameraFrameRateRange] = []
    ) {
        self.size = size
        self.fieldOfView = fieldOfView
        self.frameRateRanges = frameRateRanges
    }

    func supportsFrameRate(_ framesPerSecond: Double) -> Bool {
        frameRateRanges.contains { $0.contains(framesPerSecond) }
    }
}

enum CameraResolutionPolicy {
    /// 优先支持全部目标帧率，其次活跃帧率；固定帧率相机仍可由送帧节流控制分析频率。
    /// 在档位预算内取最清晰的格式；相同尺寸优先更宽的视野，避免额外裁切。
    /// 若镜头没有预算内的格式，取 SDK 允许的最小格式，始终不超过 SDK 上限。
    static func selectIndex(
        from formats: [CameraFormatOption],
        tier: CameraAnalysisResolution,
        sdkLimit: CameraFrameSize,
        preferredFrameRates: [Double] = []
    ) -> Int? {
        let sizeCompatible = formats.indices.filter { formats[$0].size.fits(within: sdkLimit) }
        let allFrameRates = sizeCompatible.filter { index in
            preferredFrameRates.allSatisfy { formats[index].supportsFrameRate($0) }
        }
        let activeFrameRate = sizeCompatible.filter { index in
            guard let active = preferredFrameRates.first else { return true }
            return formats[index].supportsFrameRate(active)
        }
        let supported = !allFrameRates.isEmpty ? allFrameRates
            : !activeFrameRate.isEmpty ? activeFrameRate : sizeCompatible
        let preferred = supported.filter { formats[$0].size.fits(within: tier.preferredSize) }
        let candidates = preferred.isEmpty ? supported : preferred
        return candidates.sorted { left, right in
            let lhs = formats[left]
            let rhs = formats[right]
            if lhs.size.pixelCount != rhs.size.pixelCount {
                return preferred.isEmpty
                    ? lhs.size.pixelCount < rhs.size.pixelCount
                    : lhs.size.pixelCount > rhs.size.pixelCount
            }
            if lhs.fieldOfView != rhs.fieldOfView { return lhs.fieldOfView > rhs.fieldOfView }
            return left < right
        }.first
    }
}

enum CameraZoomPolicy {
    static let preferredDisplayFactor: CGFloat = 0.8

    static func deviceFactor(
        displayMultiplier: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        guard displayMultiplier.isFinite, displayMultiplier > 0,
              minimum.isFinite, maximum.isFinite, minimum <= maximum else {
            return max(1, minimum)
        }
        let requested = preferredDisplayFactor / displayMultiplier
        return min(max(requested, minimum), maximum)
    }

    static func displayFactor(deviceFactor: CGFloat, displayMultiplier: CGFloat) -> CGFloat {
        deviceFactor * displayMultiplier
    }
}

/// Demo 的设备采集偏好；不属于 HiFace SDK 推理配置。
struct DemoCameraSettings: Sendable {
    static let resolutionKey = "HiFaceDemo.camera.analysisResolution"
    static let mirrorCoordinatesKey = "HiFaceDemo.camera.mirrorCoordinates"

    let analysisResolution: CameraAnalysisResolution
    let mirrorsOverlayCoordinates: Bool

    static func load(
        defaults: UserDefaults = .standard,
        defaultAnalysisResolution: CameraAnalysisResolution = .medium
    ) -> DemoCameraSettings {
        DemoCameraSettings(
            analysisResolution: CameraAnalysisResolution(
                storedValue: defaults.string(forKey: resolutionKey),
                fallback: defaultAnalysisResolution
            ),
            mirrorsOverlayCoordinates: defaults.bool(forKey: mirrorCoordinatesKey)
        )
    }
}
