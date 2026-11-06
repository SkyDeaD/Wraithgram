import Foundation
import XCTest

// Host tests of the choices that replaced switch pairs and the nine screen-edge rows (2026-10-27),
// compiled together with Settings/Sources/WGAppearanceChoices.swift only.
// Run: ./build-input/bazel-9.2.0-darwin-arm64 test //Wraithgram/Features/Appearance:WGAppearanceChoicesTests

final class WGAppearanceChoicesTests: XCTestCase {
    // MARK: Hidden reactions and formatting

    func testHiddenReactionsFromTwoSwitches() {
        XCTAssertNil(WGHiddenReactions.merged(inChats: nil, inChannels: nil))
        XCTAssertNil(WGHiddenReactions.merged(inChats: false, inChannels: false))
        XCTAssertEqual(WGHiddenReactions.merged(inChats: true, inChannels: nil), .chats)
        XCTAssertEqual(WGHiddenReactions.merged(inChats: false, inChannels: true), .channels)
        XCTAssertEqual(WGHiddenReactions.merged(inChats: true, inChannels: true), .all)
    }

    func testHiddenReactionsPlaces() {
        for value in WGHiddenReactions.allCases {
            XCTAssertEqual(WGHiddenReactions(inChats: value.inChats, inChannels: value.inChannels), value)
        }
        XCTAssertFalse(WGHiddenReactions.off.inChats || WGHiddenReactions.off.inChannels)
        XCTAssertTrue(WGHiddenReactions.chats.inChats && !WGHiddenReactions.chats.inChannels)
        XCTAssertTrue(!WGHiddenReactions.channels.inChats && WGHiddenReactions.channels.inChannels)
        XCTAssertTrue(WGHiddenReactions.all.inChats && WGHiddenReactions.all.inChannels)
    }

    func testHiddenFormattingFromTwoSwitches() {
        XCTAssertNil(WGHiddenFormatting.merged(inIncoming: nil, inOutgoing: false))
        XCTAssertEqual(WGHiddenFormatting.merged(inIncoming: true, inOutgoing: nil), .incoming)
        XCTAssertEqual(WGHiddenFormatting.merged(inIncoming: nil, inOutgoing: true), .outgoing)
        XCTAssertEqual(WGHiddenFormatting.merged(inIncoming: true, inOutgoing: true), .all)
        for value in WGHiddenFormatting.allCases {
            XCTAssertEqual(WGHiddenFormatting(inIncoming: value.inIncoming, inOutgoing: value.inOutgoing), value)
        }
    }

    func testRawValuesAreStable() {
        // Stored in the settings file: never rename.
        XCTAssertEqual(WGHiddenReactions.allCases.map { $0.rawValue }, ["off", "chats", "channels", "all"])
        XCTAssertEqual(WGHiddenFormatting.allCases.map { $0.rawValue }, ["off", "incoming", "outgoing", "all"])
        XCTAssertEqual(WGEdgeStyle.allCases.map { $0.rawValue }, ["off", "blur", "gradient"])
    }

    // MARK: Screen edges

    func testNothingStoredWritesNothing() {
        XCTAssertNil(WGEdgeMerge.merged(WGEdgeMerge.Old()))
        XCTAssertNil(WGEdgeMerge.merged(WGEdgeMerge.Old(blur: false, blurColor: "", gradient: false)))
    }

    func testBlurKeepsItsValues() {
        let merge = WGEdgeMerge.merged(WGEdgeMerge.Old(blur: true, blurColor: "112233", blurSize: 120.0, blurIntensity: 60.0, gradientColor: "445566", gradientSize: 30.0))
        XCTAssertEqual(merge, WGEdgeMerge(style: .blur, color: "112233", size: 120.0, intensity: 60.0))
    }

    func testBlurWithDefaultsKeepsTheOldBlurHeight() {
        XCTAssertEqual(WGEdgeMerge.merged(WGEdgeMerge.Old(blur: true)), WGEdgeMerge(style: .blur, size: 80.0))
    }

    func testGradientKeepsItsOldDefaultHeight() {
        // The gradient was 40 pt by default; the group's default is 80, so 40 is written.
        let merge = WGEdgeMerge.merged(WGEdgeMerge.Old(blurSize: 100.0, gradient: true, gradientHideInChatList: true))
        XCTAssertEqual(merge, WGEdgeMerge(style: .gradient, size: 40.0, hideInChatList: true))
    }

    func testBothOnPicksTheBlur() {
        let merge = WGEdgeMerge.merged(WGEdgeMerge.Old(blur: true, blurIntensity: 70.0, gradient: true, gradientColor: "AABBCC", gradientSize: 20.0, gradientIntensity: 30.0))
        XCTAssertEqual(merge?.style, .blur)
        XCTAssertNil(merge?.color)
        XCTAssertEqual(merge?.size, 80.0)
        XCTAssertEqual(merge?.intensity, 70.0)
    }

    func testBothOffKeepsTunedValuesBlurFirst() {
        let merge = WGEdgeMerge.merged(WGEdgeMerge.Old(blur: false, blurSize: 64.0, gradient: false, gradientColor: "AABBCC", gradientSize: 20.0, gradientIntensity: 30.0))
        XCTAssertEqual(merge, WGEdgeMerge(style: .off, color: "AABBCC", size: 64.0, intensity: 30.0))
    }

    func testValuesAreClamped() {
        let merge = WGEdgeMerge.merged(WGEdgeMerge.Old(blur: true, blurSize: 500.0, blurIntensity: -5.0))
        XCTAssertEqual(merge?.size, WGEdgeStyle.sizeRange.upperBound)
        XCTAssertEqual(merge?.intensity, 0.0)
        XCTAssertEqual(WGEdgeMerge.merged(WGEdgeMerge.Old(gradient: true, gradientSize: 1.0))?.size, WGEdgeStyle.sizeRange.lowerBound)
    }
}
