import Foundation
#if !DRIFT_STANDALONE_TESTS
import XCTest
#endif
@testable import DriftCore

final class VideoQualityTests: XCTestCase {
    func testAllQualityLimits() {
        let expectations: [(VideoQuality, Int, Int, Double)] = [
            (.eco, 1280, 720, 24), (.balanced, 1920, 1080, 30),
            (.smooth, 1920, 1080, 60), (.ultra, 3840, 2160, 60)
        ]
        for (quality, width, height, fps) in expectations {
            let plan = VideoImportPlan(sourceWidth: 7680, sourceHeight: 4320, sourceFrameRate: 120, quality: quality)!
            XCTAssertEqual(plan.width, width); XCTAssertEqual(plan.height, height); XCTAssertEqual(plan.framesPerSecond, fps)
        }
    }

    func testLowResolutionSourceIsNotUpscaled() {
        let plan = VideoImportPlan(sourceWidth: 640, sourceHeight: 360, sourceFrameRate: 15, quality: .ultra)!
        XCTAssertEqual(plan.width, 640); XCTAssertEqual(plan.height, 360); XCTAssertEqual(plan.framesPerSecond, 15)
    }

    func testFractionalFrameRateIsPreserved() {
        let fps = 60_000.0 / 1001
        let plan = VideoImportPlan(sourceWidth: 1920, sourceHeight: 1080, sourceFrameRate: fps, quality: .smooth)!
        XCTAssertEqual(plan.framesPerSecond, fps)
    }

    func testThirtyFPSIsNotPromotedToSixty() {
        let plan = VideoImportPlan(sourceWidth: 1920, sourceHeight: 1080, sourceFrameRate: 30, quality: .smooth)!
        XCTAssertEqual(plan.framesPerSecond, 30)
    }

    func testSlowSourceIsNotPromotedToSixty() {
        let plan = VideoImportPlan(sourceWidth: 1920, sourceHeight: 1080, sourceFrameRate: 0.5, quality: .smooth)!
        XCTAssertEqual(plan.framesPerSecond, 0.5)
    }

    func testPortraitKeepsAspectAndEvenDimensions() {
        let plan = VideoImportPlan(sourceWidth: 1080, sourceHeight: 1920, sourceFrameRate: 60, quality: .smooth)!
        XCTAssertEqual(plan.width, 606); XCTAssertEqual(plan.height, 1080); XCTAssertEqual(plan.framesPerSecond, 60)
    }

    func testInvalidDimensionsAreRejected() {
        XCTAssertNil(VideoImportPlan(sourceWidth: 0, sourceHeight: 1080, sourceFrameRate: 60, quality: .smooth))
        XCTAssertNil(VideoImportPlan(sourceWidth: .nan, sourceHeight: 1080, sourceFrameRate: 60, quality: .smooth))
        XCTAssertNil(VideoImportPlan(sourceWidth: 1920, sourceHeight: .infinity, sourceFrameRate: 60, quality: .smooth))
    }

    func testUnknownFrameRateFallsBackToQualityCeiling() {
        let plan = VideoImportPlan(sourceWidth: 1920, sourceHeight: 1080, sourceFrameRate: .nan, quality: .smooth)!
        XCTAssertEqual(plan.framesPerSecond, 60)
    }

    func testQualityPreferenceRoundTrip() throws {
        for quality in VideoQuality.allCases {
            XCTAssertEqual(try JSONDecoder().decode(VideoQuality.self, from: JSONEncoder().encode(quality)), quality)
        }
    }
}
