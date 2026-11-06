import Foundation
import XCTest

final class WGAntiDeleteQuoteTests: XCTestCase {
    private enum Style: Equatable {
        case link
    }

    private func kindName(_ kind: WGQuoteSpanKind<Style>) -> String {
        switch kind {
        case .blockQuote:
            return "quote"
        case .bold:
            return "bold"
        case .authorLink:
            return "author"
        case let .original(style):
            return "\(style)"
        }
    }

    func testGroupQuoteHasLinkedBoldAuthorAndShiftedEntities() {
        let result = WGAntiDeleteQuoteBuilder.build(author: "Аня", linksAuthor: true, quotedText: "привет", messageText: "ок", messageSpans: [WGQuoteSpan(range: 0 ..< 2, kind: .original(Style.link))], maximumLength: 4096)
        guard let result else {
            return XCTFail("no quote")
        }
        XCTAssertEqual(result.text, "Аня\nпривет\nок")
        let spans = result.spans.map { (self.kindName($0.kind), $0.range) }
        XCTAssertEqual(spans.map { $0.0 }, ["quote", "bold", "author", "link"])
        XCTAssertEqual(spans[0].1, 0 ..< 10)
        XCTAssertEqual(spans[1].1, 0 ..< 3)
        XCTAssertEqual(spans[2].1, 0 ..< 3)
        XCTAssertEqual(spans[3].1, 11 ..< 13)
    }

    func testOneToOneQuoteHasNoAuthorLine() {
        let result = WGAntiDeleteQuoteBuilder.build(author: nil, linksAuthor: false, quotedText: "x", messageText: "", messageSpans: [WGQuoteSpan<Style>](), maximumLength: 4096)
        XCTAssertEqual(result?.text, "x")
        XCTAssertEqual(result?.spans.map { self.kindName($0.kind) }, ["quote"])
        // A name the account can not mention: bold, no link.
        let unlinked = WGAntiDeleteQuoteBuilder.build(author: "Канал", linksAuthor: false, quotedText: "x", messageText: "", messageSpans: [WGQuoteSpan<Style>](), maximumLength: 4096)
        XCTAssertEqual(unlinked?.spans.map { self.kindName($0.kind) }, ["quote", "bold"])
    }

    func testLongQuoteIsCutAtCharacterBoundary() {
        let quoted = String(repeating: "👍", count: 1000)
        let result = WGAntiDeleteQuoteBuilder.build(author: "A", linksAuthor: false, quotedText: quoted, messageText: "m", messageSpans: [WGQuoteSpan<Style>](), maximumLength: 4096)
        guard let result else {
            return XCTFail("no quote")
        }
        let lines = result.text.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].hasSuffix("…"))
        XCTAssertLessThanOrEqual((lines[1] as NSString).length, WGAntiDeleteQuoteBuilder.maximumQuoteLength)
        // Whole emoji only: an odd UTF-16 cut would leave a broken surrogate.
        XCTAssertEqual(lines[1].dropLast().count * 2, (String(lines[1].dropLast()) as NSString).length)
    }

    func testNothingToQuoteOrNoRoomGivesNil() {
        XCTAssertNil(WGAntiDeleteQuoteBuilder.build(author: "A", linksAuthor: true, quotedText: "", messageText: "m", messageSpans: [WGQuoteSpan<Style>](), maximumLength: 4096))
        let text = String(repeating: "a", count: 1020)
        XCTAssertNil(WGAntiDeleteQuoteBuilder.build(author: "Author", linksAuthor: false, quotedText: "q", messageText: text, messageSpans: [WGQuoteSpan<Style>](), maximumLength: 1024))
    }
}
