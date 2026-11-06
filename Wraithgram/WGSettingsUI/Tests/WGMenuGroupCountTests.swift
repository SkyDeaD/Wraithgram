import Foundation
import XCTest

// Host tests of the summary on an expandable row without a master switch (2026-10-27), compiled
// together with Sources/Model/WGMenuGroupCount.swift only.
// Run: ./build-input/bazel-9.2.0-darwin-arm64 test //Wraithgram/WGSettingsUI:WGSettingsUIModelTests

final class WGMenuGroupCountTests: XCTestCase {
    private func hidden(_ count: WGMenuGroupCount) -> String {
        return "скрыто: \(count.selected) из \(count.total)"
    }

    func testCountsTheVisibleChildren() {
        XCTAssertEqual(WGMenuGroupCount(values: [true, false, true, false]), WGMenuGroupCount(selected: 2, total: 4))
        XCTAssertEqual(WGMenuGroupCount(values: [false, false, false, false]), WGMenuGroupCount(selected: 0, total: 4))
        XCTAssertEqual(WGMenuGroupCount(values: [true, true, true, true]), WGMenuGroupCount(selected: 4, total: 4))
        XCTAssertEqual(WGMenuGroupCount(values: []), WGMenuGroupCount(selected: 0, total: 0))
    }

    func testNothingOnShowsNothing() {
        var calls = 0
        let summary = WGMenuGroupCount(values: [false, false, false, false]).summary { count in
            calls += 1
            return self.hidden(count)
        }
        XCTAssertNil(summary)
        // The feature's text is not even built.
        XCTAssertEqual(calls, 0)
        XCTAssertNil(WGMenuGroupCount(values: []).summary(self.hidden))
    }

    func testSummaryOfWhatIsOn() {
        XCTAssertEqual(WGMenuGroupCount(values: [true, false, true, false]).summary(self.hidden), "скрыто: 2 из 4")
        XCTAssertEqual(WGMenuGroupCount(values: [false, false, false, true]).summary(self.hidden), "скрыто: 1 из 4")
        XCTAssertEqual(WGMenuGroupCount(values: [true, true, true, true]).summary(self.hidden), "скрыто: 4 из 4")
    }
}
