import Foundation
import XCTest

// Host tests of «Записывать звонки» as one choice (2026-10-27), compiled together with
// Sources/Settings/WGCallRecordingMode.swift only.
// Run: ./build-input/bazel-9.2.0-darwin-arm64 test //Wraithgram/Features/CallsMedia:WGCallRecordingModeTests

final class WGCallRecordingModeTests: XCTestCase {
    func testMergeOfTheTwoOldSwitches() {
        // Nothing stored: keep the default.
        XCTAssertNil(WGCallRecordingMode.merged(audio: nil, video: nil))
        // Video on wins, also without audio (a video-only setting is not a choice any more).
        XCTAssertEqual(WGCallRecordingMode.merged(audio: true, video: true), .audioAndVideo)
        XCTAssertEqual(WGCallRecordingMode.merged(audio: false, video: true), .audioAndVideo)
        XCTAssertEqual(WGCallRecordingMode.merged(audio: nil, video: true), .audioAndVideo)
        // Audio only.
        XCTAssertEqual(WGCallRecordingMode.merged(audio: true, video: false), .audio)
        XCTAssertEqual(WGCallRecordingMode.merged(audio: true, video: nil), .audio)
        // Both stored off, or one stored off and the other never written.
        XCTAssertEqual(WGCallRecordingMode.merged(audio: false, video: false), .off)
        XCTAssertEqual(WGCallRecordingMode.merged(audio: false, video: nil), .off)
        XCTAssertEqual(WGCallRecordingMode.merged(audio: nil, video: false), .off)
    }

    func testWhatEachChoiceRecords() {
        XCTAssertFalse(WGCallRecordingMode.off.isOn)
        XCTAssertFalse(WGCallRecordingMode.off.recordsVideo)
        XCTAssertTrue(WGCallRecordingMode.audio.isOn)
        XCTAssertFalse(WGCallRecordingMode.audio.recordsVideo)
        XCTAssertTrue(WGCallRecordingMode.audioAndVideo.isOn)
        XCTAssertTrue(WGCallRecordingMode.audioAndVideo.recordsVideo)
    }

    func testStoredValues() {
        // The raw values are what `calls.record` stores: they must not change.
        XCTAssertEqual(WGCallRecordingMode.allCases.map(\.rawValue), ["off", "audio", "audioAndVideo"])
        for mode in WGCallRecordingMode.allCases {
            XCTAssertEqual(WGCallRecordingMode.resolved(mode.rawValue), mode)
        }
        XCTAssertEqual(WGCallRecordingMode.resolved(""), .off)
        XCTAssertEqual(WGCallRecordingMode.resolved("video"), .off)
    }
}
