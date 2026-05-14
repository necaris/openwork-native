import XCTest
@testable import OpenWorkNative

final class SSEParserTests: XCTestCase {
    func testParsesSingleDataEvent() {
        let events = SSEParser.events(from: [
            "data: {\"type\":\"server.connected\"}",
            ""
        ])

        XCTAssertEqual(events, ["{\"type\":\"server.connected\"}"])
    }

    func testCombinesMultilineDataEvent() {
        let events = SSEParser.events(from: [
            "data: {\"type\":",
            "data: \"todo.updated\"}",
            ""
        ])

        XCTAssertEqual(events, ["{\"type\":\n\"todo.updated\"}"])
    }
}
