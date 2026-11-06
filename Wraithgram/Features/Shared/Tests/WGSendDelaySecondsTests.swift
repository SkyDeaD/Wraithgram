import Foundation
import XCTest

// Host tests of the one send delay (since 2026-10-27), compiled together with
// Sources/GhostMode/WGSendDelaySeconds.swift (target WGFeaturesSharedTests).
// Run: ./build-input/bazel-9.2.0-darwin-arm64 test //Wraithgram/Features/Shared:WGFeaturesSharedTests

final class WGSendDelaySecondsTests: XCTestCase {
    func testDefaultIsTheLargerOldDefault() {
        XCTAssertEqual(WGSendDelaySeconds.defaultValue, 20.0)
        XCTAssertTrue(WGSendDelaySeconds.range.contains(WGSendDelaySeconds.defaultValue))
    }

    func testMergeTakesTheLargerOfTheTwo() {
        // Nothing stored: the default already is max(12, 20).
        XCTAssertNil(WGSendDelaySeconds.merged(text: nil, media: nil))
        XCTAssertEqual(WGSendDelaySeconds.merged(text: 30.0, media: nil), 30.0)
        XCTAssertEqual(WGSendDelaySeconds.merged(text: 15.0, media: nil), 20.0)
        XCTAssertEqual(WGSendDelaySeconds.merged(text: nil, media: 90.0), 90.0)
        XCTAssertEqual(WGSendDelaySeconds.merged(text: 45.0, media: 25.0), 45.0)
        XCTAssertEqual(WGSendDelaySeconds.merged(text: 12.0, media: 180.0), 180.0)
    }

    func testValuesStayInTheRange() {
        XCTAssertEqual(WGSendDelaySeconds.merged(text: 500.0, media: nil), 180.0)
        XCTAssertEqual(WGSendDelaySeconds.clamped(3.0), 12.0)
        XCTAssertEqual(WGSendDelaySeconds.clamped(.nan), WGSendDelaySeconds.defaultValue)
        XCTAssertEqual(WGSendDelaySeconds.clamped(61.0), 61.0)
    }
}
