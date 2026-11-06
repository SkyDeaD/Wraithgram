import Foundation
import XCTest

final class WGKeysTests: XCTestCase {
    func testPeerKeyStringRoundTrip() {
        let key = WGPeerKey(namespace: 2, id: 1234567890)
        XCTAssertEqual(key?.stringValue, "2:1234567890")
        XCTAssertEqual(WGPeerKey(string: "2:1234567890"), key)
        XCTAssertEqual(WGPeerKey(string: "3:-5"), WGPeerKey(namespace: 3, id: -5))
    }

    func testPeerKeyRejectsNonCanonicalText() {
        for text in ["", "2", ":5", "2:", "8:1", "-1:1", "02:5", "2:05", "2:+5", " 2:5", "2:5 ", "2:5:6", "a:b", "2:-0"] {
            XCTAssertNil(WGPeerKey(string: text), text)
        }
        XCTAssertNil(WGPeerKey(namespace: 8, id: 1))
        XCTAssertNil(WGPeerKey(namespace: -1, id: 1))
    }

    func testMessageKeyStringRoundTrip() {
        let peer = WGPeerKey(namespace: 0, id: 777000)!
        let key = WGMessageKey(peer: peer, namespace: 0, id: 1234)
        XCTAssertEqual(key.stringValue, "0:777000/0:1234")
        XCTAssertEqual(WGMessageKey(string: "0:777000/0:1234"), key)
        XCTAssertEqual(WGMessageKey(string: "2:5/3:-7")?.namespace, 3)
        for text in ["0:777000", "0:777000/", "0:777000/0", "0:777000/0:1234/1", "9:1/0:1", "0:1/0:99999999999"] {
            XCTAssertNil(WGMessageKey(string: text), text)
        }
    }

    func testCodableUsesTheStringForms() throws {
        let peer = WGPeerKey(namespace: 1, id: 42)!
        let message = WGMessageKey(peer: peer, namespace: 0, id: 7)
        let account = WGAccountID(rawValue: -9)
        let encoder = JSONEncoder()
        XCTAssertEqual(String(decoding: try encoder.encode(peer), as: UTF8.self), "\"1:42\"")
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: try encoder.encode(message)), "1:42/0:7")
        XCTAssertEqual(String(decoding: try encoder.encode(account), as: UTF8.self), "-9")

        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(WGPeerKey.self, from: Data("\"1:42\"".utf8)), peer)
        XCTAssertEqual(try decoder.decode(WGMessageKey.self, from: Data("\"1:42/0:7\"".utf8)), message)
        XCTAssertEqual(try decoder.decode(WGAccountID.self, from: Data("-9".utf8)), account)
        XCTAssertThrowsError(try decoder.decode(WGPeerKey.self, from: Data("\"9:1\"".utf8)))
        XCTAssertEqual(try decoder.decode(Set<WGPeerKey>.self, from: Data("[\"1:42\"]".utf8)), [peer])
    }

    func testOrdering() {
        let a = WGPeerKey(namespace: 0, id: 5)!
        let b = WGPeerKey(namespace: 0, id: 6)!
        let c = WGPeerKey(namespace: 1, id: 1)!
        XCTAssertEqual([c, b, a].sorted(), [a, b, c])
        XCTAssertTrue(WGMessageKey(peer: a, namespace: 1, id: 1) < WGMessageKey(peer: b, namespace: 0, id: 0))
        XCTAssertTrue(WGAccountID(rawValue: -1) < WGAccountID(rawValue: 1))
    }

    /// Vectors computed from the bit layout of `PeerId.init(_ n: Int64)` / `_toInt64()` in
    /// Postbox/Sources/Peer.swift. The TelegramCore bridge re-checks them against Postbox itself.
    func testLegacyInt64Vectors() {
        let vectors: [(Int32, Int64, Int64)] = [
            (0, 777000, 777000),
            (2, 1234567890, 9824502482),
            (3, -5, 17179869179),
            (0, 4294967301, 34359738373),
            (7, 0, 9223372032559808512),
            (2, 1000000000000, 7983616823296),
            (2, 1234567890123, 9871747122379),
            (0, 5000000000, 35064771072)
        ]
        for (namespace, id, legacy) in vectors {
            let key = WGPeerKey(namespace: namespace, id: id)!
            XCTAssertEqual(WGLegacyKeys.peerKey(fromLegacyInt64: legacy), key, "\(legacy)")
            XCTAssertEqual(WGLegacyKeys.legacyInt64(of: key), legacy, "\(key)")
        }
        XCTAssertNil(WGLegacyKeys.legacyInt64(of: WGPeerKey(namespace: 3, id: -5000000000)!))
    }

    func testLegacyMessageKeys() {
        let key = WGLegacyKeys.messageKey(fromLegacyString: "9824502482_15")
        XCTAssertEqual(key?.peer, WGPeerKey(namespace: 2, id: 1234567890))
        XCTAssertEqual(key?.namespace, 0)
        XCTAssertEqual(key?.id, 15)
        XCTAssertEqual(WGLegacyKeys.messageKey(fromLegacyString: "777000_3", messageNamespace: 1)?.namespace, 1)
        for text in ["", "777000", "_3", "777000_", "777000_x", "a_1", "777000_99999999999"] {
            XCTAssertNil(WGLegacyKeys.messageKey(fromLegacyString: text), text)
        }
        XCTAssertEqual(WGLegacyKeys.peerKey(fromRawId: 1234567890, namespace: 2), WGPeerKey(namespace: 2, id: 1234567890))
        XCTAssertNil(WGLegacyKeys.peerKey(fromRawId: 1, namespace: 9))
    }

    func testAccountIdStringForm() {
        XCTAssertEqual(WGAccountID(rawValue: -42).stringValue, "-42")
        XCTAssertEqual(WGAccountID(string: "-42"), WGAccountID(rawValue: -42))
        XCTAssertNil(WGAccountID(string: "042"))
        XCTAssertNil(WGAccountID(string: "x"))
    }
}
