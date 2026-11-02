#if !DRIFT_STANDALONE_TESTS
import XCTest
#endif
@testable import DriftCore

final class CoverageTests: XCTestCase {
    let screen = DesktopRect(x: 0, y: 0, width: 100, height: 100)

    func testTwoOverlappingHalfWindowsDoNotHideTheWholeDesktop() {
        let half = DesktopRect(x: 0, y: 0, width: 50, height: 100)
        XCTAssertEqual(DesktopCoverage.fraction(of: screen, coveredBy: [half, half]), 0.5)
    }

    func testSplitViewCoversDesktop() {
        let windows = [DesktopRect(x: 0, y: 0, width: 50, height: 100),
                       DesktopRect(x: 50, y: 0, width: 50, height: 100)]
        XCTAssertEqual(DesktopCoverage.fraction(of: screen, coveredBy: windows), 1)
    }

    func testOtherDisplayAndOutOfBoundsWindowsAreClipped() {
        let windows = [DesktopRect(x: -100, y: -100, width: 150, height: 200),
                       DesktopRect(x: 200, y: 0, width: 100, height: 100)]
        XCTAssertEqual(DesktopCoverage.fraction(of: screen, coveredBy: windows), 0.5)
    }

    func testEmptyAndInvalidScreens() {
        XCTAssertEqual(DesktopCoverage.fraction(of: screen, coveredBy: []), 0)
        XCTAssertEqual(DesktopCoverage.fraction(of: .init(x: 0, y: 0, width: 0, height: 0), coveredBy: [screen]), 0)
    }
}
