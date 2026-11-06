import Foundation
import XCTest

// Host tests of «Без перехода к следующему каналу и теме» as one switch (2026-10-27), compiled together
// with Sources/Messages/WGScrollToNextMerge.swift (target WGFeaturesSharedTests).
// Run: ./build-input/bazel-9.2.0-darwin-arm64 test //Wraithgram/Features/Shared:WGFeaturesSharedTests

final class WGScrollToNextMergeTests: XCTestCase {
    func testEitherOldSwitchTurnsTheOneOn() {
        XCTAssertNil(WGScrollToNextMerge.merged(channel: nil, topic: nil))
        XCTAssertEqual(WGScrollToNextMerge.merged(channel: true, topic: nil), true)
        XCTAssertEqual(WGScrollToNextMerge.merged(channel: nil, topic: true), true)
        XCTAssertEqual(WGScrollToNextMerge.merged(channel: true, topic: false), true)
        XCTAssertEqual(WGScrollToNextMerge.merged(channel: false, topic: true), true)
        XCTAssertEqual(WGScrollToNextMerge.merged(channel: true, topic: true), true)
    }

    func testBothStoredOffStaysOff() {
        XCTAssertEqual(WGScrollToNextMerge.merged(channel: false, topic: false), false)
        XCTAssertEqual(WGScrollToNextMerge.merged(channel: false, topic: nil), false)
        XCTAssertEqual(WGScrollToNextMerge.merged(channel: nil, topic: false), false)
    }
}
