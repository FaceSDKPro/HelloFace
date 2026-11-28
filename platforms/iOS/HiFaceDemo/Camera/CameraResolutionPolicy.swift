import Foundation

/// Quality presets for face analysis; dimensions are selection budgets, not exact camera-format
/// requirements.
/// 面向人脸分析的画质档位；尺寸是选型预算，不要求镜头提供完全相同的格式。
enum CameraAnalysisResolution: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    init(storedValue: String?, fallback: CameraAnalysisResolution = .low) {
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
        let size = preferredSize
        return "\(size.width) × \(size.height)"
    }

    var preferredSize: CameraFrameSize {
        switch self {
        case .low: CameraFrameSize(width: 640, height: 480)
        case .medium: CameraFrameSize(width: 1280, height: 960)
        case .high: CameraFrameSize(width: 1440, height: 1080)
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

    /// Preserve supported target rates; prefer the lowest integer-multiple fallback to avoid extra drops
    /// from phases such as 7.5/5.
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
                // Without a usable integer multiple, retain the range ceiling rather than worsening sampling intervals
                // to reduce capture.
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
    /// Rank SDK-compatible formats by frame-rate support first: all targets, the active target, then
    /// any other rate. Within that group, prefer the largest native format within both tier dimensions.
    /// If every format in the group exceeds the tier, use the smallest. Break pixel-count ties by
    /// wider field of view. Native 4:3 and 16:9 modes compete on the same criteria.
    static func selectIndex(
        from formats: [CameraFormatOption],
        tier: CameraAnalysisResolution,
        sdkLimit: CameraFrameSize,
        preferredFrameRates: [Double] = []
    ) -> Int? {
        let budget = tier.preferredSize
        var best: (rank: (frameRate: Int, overBudget: Int, pixels: Int, fieldOfView: Float), index: Int)?
        for (index, format) in formats.enumerated() where format.size.fits(within: sdkLimit) {
            let frameRateRank: Int
            if preferredFrameRates.allSatisfy({ format.supportsFrameRate($0) }) {
                frameRateRank = 0
            } else if let active = preferredFrameRates.first, format.supportsFrameRate(active) {
                frameRateRank = 1
            } else {
                frameRateRank = 2
            }
            let fitsBudget = format.size.fits(within: budget)
            let pixelRank = fitsBudget ? -format.size.pixelCount : format.size.pixelCount
            let rank = (frameRateRank, fitsBudget ? 0 : 1, pixelRank, -format.fieldOfView)
            if best.map({ rank < $0.rank }) ?? true {
                best = (rank, index)
            }
        }
        return best?.index
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

/// Demo device-capture preferences, outside HiFace SDK inference configuration.
/// Demo 的设备采集偏好；不属于 HiFace SDK 推理配置。
struct DemoCameraSettings: Sendable {
    static let resolutionKey = "HiFaceDemo.camera.analysisResolution"
    static let mirrorCoordinatesKey = "HiFaceDemo.camera.mirrorCoordinates"

    let analysisResolution: CameraAnalysisResolution
    let mirrorsOverlayCoordinates: Bool

    static func load(
        defaults: UserDefaults = .standard,
        defaultAnalysisResolution: CameraAnalysisResolution = .low
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
