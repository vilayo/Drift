import Foundation

public struct EnergyPreferences: Codable, Equatable, Sendable {
    public var pauseOnBattery = true
    public var pauseWhenCovered = true
    public init() {}
}

public enum PauseReason: String, Codable, Sendable, CaseIterable {
    case stopped, user, sleeping, locked, lowPower, thermal, memory, lowBattery, battery, covered

    public var title: String {
        switch self {
        case .stopped: return "Wallpaper off"
        case .user: return "Paused by you"
        case .sleeping: return "Display asleep"
        case .locked: return "Mac locked"
        case .lowPower: return "Low Power Mode"
        case .thermal: return "Letting your Mac cool down"
        case .memory: return "Giving memory back to your Mac"
        case .lowBattery: return "Battery below 15%"
        case .battery: return "Saving battery"
        case .covered: return "Desktop is covered"
        }
    }
}

public struct PlaybackConditions: Sendable {
    public var enabled = false
    public var manuallyPaused = false
    public var sleeping = false
    public var locked = false
    public var lowPower = false
    public var hot = false
    public var memoryPressure = false
    public var onBattery = false
    public var batteryPercent: Int?
    public var desktopCovered = false
    public init() {}
}

public enum PlaybackPolicy {
    /// Returning nil permits playback. User preferences cannot override system protection.
    public static func pauseReason(_ state: PlaybackConditions, preferences: EnergyPreferences) -> PauseReason? {
        if !state.enabled { return .stopped }
        if state.manuallyPaused { return .user }
        if state.sleeping { return .sleeping }
        if state.locked { return .locked }
        if state.lowPower { return .lowPower }
        if state.hot { return .thermal }
        if state.memoryPressure { return .memory }
        if state.onBattery, let percent = state.batteryPercent, percent < 15 { return .lowBattery }
        if state.onBattery && preferences.pauseOnBattery { return .battery }
        if state.desktopCovered && preferences.pauseWhenCovered { return .covered }
        return nil
    }
}
