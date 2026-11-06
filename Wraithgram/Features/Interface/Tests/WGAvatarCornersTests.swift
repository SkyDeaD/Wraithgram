import Foundation
import XCTest

// Host tests of «Скругление углов» (one setting since 2026-10-27), compiled together with
// Sources/Settings/WGAvatarCorners.swift only.
// Run: ./build-input/bazel-9.2.0-darwin-arm64 test //Wraithgram/Features/Interface:WGAvatarCornersTests

final class WGAvatarCornersTests: XCTestCase {
    func testShape() {
        XCTAssertFalse(WGAvatarCorners.isSquare(WGAvatarCorners.round))
        XCTAssertEqual(WGAvatarCorners.squareness("0"), 0.0)
        XCTAssertEqual(WGAvatarCorners.squareness("50"), 0.5)
        XCTAssertEqual(WGAvatarCorners.squareness("100"), 1.0)
        XCTAssertTrue(WGAvatarCorners.isSquare("25"))
        // Garbage and out-of-range values never break the shape.
        XCTAssertEqual(WGAvatarCorners.squareness("square"), 0.0)
        XCTAssertEqual(WGAvatarCorners.squareness("250"), 1.0)
        XCTAssertEqual(WGAvatarCorners.squareness("-5"), 0.0)
    }

    func testOptionsStartWithTheCircleAndEndWithTheSquare() {
        XCTAssertEqual(WGAvatarCorners.options.first, WGAvatarCorners.round)
        XCTAssertEqual(WGAvatarCorners.options.last, "100")
    }

    func testMergeOfBuild185() {
        // Off or never touched: the circle (the default), nothing to write.
        XCTAssertNil(WGAvatarCorners.merged(square: nil, squareness: nil))
        XCTAssertNil(WGAvatarCorners.merged(square: false, squareness: "50"))
        XCTAssertNil(WGAvatarCorners.merged(square: nil, squareness: "25"))
        // On: the level, absent = the old default 100.
        XCTAssertEqual(WGAvatarCorners.merged(square: true, squareness: nil), "100")
        XCTAssertEqual(WGAvatarCorners.merged(square: true, squareness: "50"), "50")
        XCTAssertEqual(WGAvatarCorners.merged(square: true, squareness: "75"), "75")
        // An odd stored value goes to the nearest level, never to the circle.
        XCTAssertEqual(WGAvatarCorners.merged(square: true, squareness: "0"), "25")
        XCTAssertEqual(WGAvatarCorners.merged(square: true, squareness: "x"), "100")
    }

    func testOldWraithgram() {
        XCTAssertNil(WGAvatarCorners.fromLegacy(square: nil, level: 50))
        XCTAssertNil(WGAvatarCorners.fromLegacy(square: false, level: 100))
        XCTAssertEqual(WGAvatarCorners.fromLegacy(square: true, level: nil), "100")
        XCTAssertEqual(WGAvatarCorners.fromLegacy(square: true, level: 40), "50")
        XCTAssertEqual(WGAvatarCorners.fromLegacy(square: true, level: 10), "25")
        XCTAssertEqual(WGAvatarCorners.fromLegacy(square: true, level: 90), "100")
    }
}
