import Testing
@testable import OpenWorkNative

@Test func parsesSingleDataEvent() {
    let events = SSEParser.events(from: [
        "data: {\"type\":\"server.connected\"}",
        ""
    ])

    #expect(events == ["{\"type\":\"server.connected\"}"])
}

@Test func combinesMultilineDataEvent() {
    let events = SSEParser.events(from: [
        "data: {\"type\":",
        "data: \"todo.updated\"}",
        ""
    ])

    #expect(events == ["{\"type\":\n\"todo.updated\"}"])
}
