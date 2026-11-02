#if DRIFT_STANDALONE_TESTS
import Foundation
#else
import XCTest
#endif
@testable import DriftCore

final class PlaybackPolicyTests: XCTestCase {
    private var preferences = EnergyPreferences()

    func testFreshInstallDoesNotChangeDesktop() {
        XCTAssertEqual(PlaybackPolicy.pauseReason(PlaybackConditions(), preferences: preferences), .stopped)
    }

    func testACPlaybackWithNoPressureIsAllowed() {
        var state = PlaybackConditions(); state.enabled = true
        XCTAssertNil(PlaybackPolicy.pauseReason(state, preferences: preferences))
    }

    func testBatteryIsConservativeByDefault() {
        var state = PlaybackConditions(); state.enabled = true; state.onBattery = true
        XCTAssertEqual(PlaybackPolicy.pauseReason(state, preferences: preferences), .battery)
        preferences.pauseOnBattery = false
        XCTAssertNil(PlaybackPolicy.pauseReason(state, preferences: preferences))
    }

    func testLowBatteryCannotBeOverridden() {
        var state = PlaybackConditions(); state.enabled = true; state.onBattery = true
        preferences.pauseOnBattery = false
        state.batteryPercent = 14
        XCTAssertEqual(PlaybackPolicy.pauseReason(state, preferences: preferences), .lowBattery)
        state.batteryPercent = 15
        XCTAssertNil(PlaybackPolicy.pauseReason(state, preferences: preferences))
    }

    func testUnknownBatteryLevelDoesNotInventLowBattery() {
        var state = PlaybackConditions(); state.enabled = true; state.onBattery = true
        preferences.pauseOnBattery = false
        XCTAssertNil(PlaybackPolicy.pauseReason(state, preferences: preferences))
    }

    func testEverySystemProtectionIndependentlyBlocksPlayback() {
        let cases: [(WritableKeyPath<PlaybackConditions, Bool>, PauseReason)] = [
            (\.sleeping, .sleeping), (\.locked, .locked), (\.lowPower, .lowPower),
            (\.hot, .thermal), (\.memoryPressure, .memory)
        ]
        preferences.pauseOnBattery = false; preferences.pauseWhenCovered = false
        for (keyPath, reason) in cases {
            var state = PlaybackConditions(); state.enabled = true; state[keyPath: keyPath] = true
            XCTAssertEqual(PlaybackPolicy.pauseReason(state, preferences: preferences), reason)
        }
    }

    func testManualPauseSurvivesWakeAndPowerChanges() {
        var state = PlaybackConditions(); state.enabled = true; state.manuallyPaused = true
        state.sleeping = true; state.onBattery = true
        state.sleeping = false; state.onBattery = false
        XCTAssertEqual(PlaybackPolicy.pauseReason(state, preferences: preferences), .user)
    }

    func testCoveredDesktopOptionAndProtectionPriority() {
        var state = PlaybackConditions(); state.enabled = true; state.desktopCovered = true
        XCTAssertEqual(PlaybackPolicy.pauseReason(state, preferences: preferences), .covered)
        state.hot = true
        XCTAssertEqual(PlaybackPolicy.pauseReason(state, preferences: preferences), .thermal)
        preferences.pauseWhenCovered = false; state.hot = false
        XCTAssertNil(PlaybackPolicy.pauseReason(state, preferences: preferences))
    }

    func testPreferencesRoundTrip() throws {
        preferences.pauseOnBattery = false
        XCTAssertEqual(try JSONDecoder().decode(EnergyPreferences.self, from: JSONEncoder().encode(preferences)), preferences)
    }
}
