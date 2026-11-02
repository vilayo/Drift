// Runs the SAME test methods on Macs with Command Line Tools but no XCTest framework.
import Foundation

class XCTestCase {}
var failureCount = 0

func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected {
        failureCount += 1
        fputs("FAIL \(file):\(line) expected \(expected), got \(actual)\n", stderr)
    }
}

func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if let value {
        failureCount += 1
        fputs("FAIL \(file):\(line) expected nil, got \(value)\n", stderr)
    }
}

@main enum CoreCheckRunner {
    static func main() {
        let checks: [(String, () throws -> Void)] = [
            ("fresh install", { PlaybackPolicyTests().testFreshInstallDoesNotChangeDesktop() }),
            ("AC playback", { PlaybackPolicyTests().testACPlaybackWithNoPressureIsAllowed() }),
            ("battery defaults", { PlaybackPolicyTests().testBatteryIsConservativeByDefault() }),
            ("low battery boundary", { PlaybackPolicyTests().testLowBatteryCannotBeOverridden() }),
            ("unknown battery", { PlaybackPolicyTests().testUnknownBatteryLevelDoesNotInventLowBattery() }),
            ("all system protections", { PlaybackPolicyTests().testEverySystemProtectionIndependentlyBlocksPlayback() }),
            ("persistent manual pause", { PlaybackPolicyTests().testManualPauseSurvivesWakeAndPowerChanges() }),
            ("coverage preference and priority", { PlaybackPolicyTests().testCoveredDesktopOptionAndProtectionPriority() }),
            ("preferences persistence", { try PlaybackPolicyTests().testPreferencesRoundTrip() }),
            ("overlap union", { CoverageTests().testTwoOverlappingHalfWindowsDoNotHideTheWholeDesktop() }),
            ("split view", { CoverageTests().testSplitViewCoversDesktop() }),
            ("multiple display clipping", { CoverageTests().testOtherDisplayAndOutOfBoundsWindowsAreClipped() }),
            ("empty coverage", { CoverageTests().testEmptyAndInvalidScreens() })
        ]
        for (name, check) in checks {
            let before = failureCount
            do { try check() }
            catch { failureCount += 1; fputs("FAIL \(name): \(error)\n", stderr) }
            if before == failureCount { print("PASS \(name)") }
        }
        print("\(checks.count) checks, \(failureCount) failures")
        exit(failureCount == 0 ? 0 : 1)
    }
}
