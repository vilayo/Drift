import Foundation

public enum VideoQuality: String, Codable, CaseIterable, Sendable {
    case eco, balanced, smooth, ultra

    public var title: String {
        switch self {
        case .eco: return "Eco · 720p / 24 fps"
        case .balanced: return "Balanced · 1080p / 30 fps"
        case .smooth: return "Smooth · 1080p / 60 fps"
        case .ultra: return "Ultra · 4K / 60 fps"
        }
    }

    public var maximumWidth: Int { self == .ultra ? 3840 : (self == .eco ? 1280 : 1920) }
    public var maximumHeight: Int { self == .ultra ? 2160 : (self == .eco ? 720 : 1080) }
    public var maximumFrameRate: Int {
        switch self {
        case .eco: return 24
        case .balanced: return 30
        case .smooth, .ultra: return 60
        }
    }

    public var explanation: String {
        switch self {
        case .eco: return "Lowest resource use. Applies to new imports."
        case .balanced: return "Sharper video at up to 30 fps. Applies to new imports."
        case .smooth: return "Full HD at up to 60 fps. Uses more power than Eco."
        case .ultra: return "Up to 4K at 60 fps. Highest memory and power use."
        }
    }
}

public struct VideoImportPlan: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let framesPerSecond: Double

    /// Source dimensions must already include its orientation transform.
    /// Never upscale a source or manufacture frames to reach a preset's ceiling.
    public init?(sourceWidth: Double, sourceHeight: Double, sourceFrameRate: Double, quality: VideoQuality) {
        guard sourceWidth.isFinite, sourceHeight.isFinite, sourceWidth >= 2, sourceHeight >= 2 else { return nil }
        let scale = min(1, min(Double(quality.maximumWidth) / sourceWidth, Double(quality.maximumHeight) / sourceHeight))
        width = max(2, Int(sourceWidth * scale) / 2 * 2)
        height = max(2, Int(sourceHeight * scale) / 2 * 2)
        framesPerSecond = sourceFrameRate.isFinite && sourceFrameRate > 0
            ? min(Double(quality.maximumFrameRate), sourceFrameRate) : Double(quality.maximumFrameRate)
    }
}
