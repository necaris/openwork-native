import Foundation
import Testing
@testable import OpenWorkNative

// Integration tests that drive AppState through a full prompt cycle the way the
// app does — sendPrompt issues the HTTP POST, then a sequence of SSE events
// is fed into apply(_:) and we assert the resulting transcript.

@MainActor
@Test func sendPromptPostsToPromptAsyncWithDirectory() async throws {
    let state = makeState()
    seedSession(state, sessionID: "ses_1")
    state.selectedSessionID = "ses_1"

    let mock = state.client!.networking as! RecordingNetworking

    state.sendPrompt("hello world")
    try await waitForRequest(matching: { $0.url?.path == "/session/ses_1/prompt_async" }, in: mock)

    let request = try #require(mock.requests.last { $0.url?.path == "/session/ses_1/prompt_async" })
    #expect(request.httpMethod == "POST")
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
    #expect(components?.queryItems?.first(where: { $0.name == "directory" })?.value == "/tmp/workspace")
    let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
    let parts = body?["parts"] as? [[String: Any]]
    #expect(parts?.first?["type"] as? String == "text")
    #expect(parts?.first?["text"] as? String == "hello world")
}

@MainActor
@Test func sseEventStreamUrlIncludesDirectoryQuery() {
    let state = makeState()
    let request = state.client!.makeEventRequest()
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
    #expect(components?.path == "/event")
    #expect(components?.queryItems?.first(where: { $0.name == "directory" })?.value == "/tmp/workspace")
}

@MainActor
@Test func sendPromptThenStreamingEventsBuildTranscript() async throws {
    let state = makeState()
    seedSession(state, sessionID: "ses_1")
    state.selectedSessionID = "ses_1"

    state.sendPrompt("hi")

    // Local stubs land immediately: user prompt + streaming assistant placeholder.
    #expect(state.sessions[0].messages.count == 2)
    #expect(state.sessions[0].messages[0].role == .user)
    #expect(state.sessions[0].messages[0].content == "hi")
    #expect(state.sessions[0].messages[0].id.hasPrefix("local-user-"))
    #expect(state.sessions[0].messages[1].role == .assistant)
    #expect(state.sessions[0].messages[1].isStreaming)
    #expect(state.sessions[0].messages[1].id.hasPrefix("stream-"))

    // 1. server echoes the user message (no text yet — info only)
    state.apply(messageUpdated(sessionID: "ses_1", messageID: "msg_u", role: "user"))
    // 2. server emits the user text as a single part
    state.apply(messagePartUpdated(sessionID: "ses_1", messageID: "msg_u", partID: "prt_u", text: "hi"))
    // 3. assistant message starts
    state.apply(messageUpdated(sessionID: "ses_1", messageID: "msg_a", role: "assistant"))
    // 4. assistant streams a tiny text part
    state.apply(messagePartUpdated(sessionID: "ses_1", messageID: "msg_a", partID: "prt_a", text: "Hello"))
    // 5. session goes idle
    state.apply(sessionIdle(sessionID: "ses_1"))

    let messages = state.sessions[0].messages
    #expect(messages.count == 2, "transcript should hold exactly one user + one assistant message, got \(messages.count): \(messages.map { "\($0.role.rawValue):\($0.id):\($0.content)" })")
    #expect(messages[0].role == .user)
    #expect(messages[0].id == "msg_u")
    #expect(messages[0].content == "hi")
    #expect(messages[1].role == .assistant)
    #expect(messages[1].id == "msg_a")
    #expect(messages[1].content == "Hello")
    #expect(messages[1].isStreaming == false)
}

@MainActor
@Test func messagePartDeltaAccumulatesAssistantText() async {
    let state = makeState()
    seedSession(state, sessionID: "ses_1")
    state.selectedSessionID = "ses_1"
    state.sendPrompt("stream this please")

    state.apply(messageUpdated(sessionID: "ses_1", messageID: "msg_u", role: "user"))
    state.apply(messagePartUpdated(sessionID: "ses_1", messageID: "msg_u", partID: "prt_u", text: "stream this please"))
    state.apply(messageUpdated(sessionID: "ses_1", messageID: "msg_a", role: "assistant"))

    // Three streaming deltas, accumulating to "Hello world".
    state.apply(messagePartDelta(sessionID: "ses_1", messageID: "msg_a", partID: "prt_a", delta: "Hello"))
    state.apply(messagePartDelta(sessionID: "ses_1", messageID: "msg_a", partID: "prt_a", delta: " "))
    state.apply(messagePartDelta(sessionID: "ses_1", messageID: "msg_a", partID: "prt_a", delta: "world"))

    let assistant = state.sessions[0].messages.last
    #expect(assistant?.role == .assistant)
    #expect(assistant?.content == "Hello world")
}

@MainActor
@Test func sessionUpdatedEventRefreshesCostTokensAndModel() {
    let state = makeState()
    seedSession(state, sessionID: "ses_1")

    state.apply(sessionUpdated(
        sessionID: "ses_1",
        cost: 0.012,
        tokens: (input: 1234, output: 56, reasoning: 7),
        model: (modelID: "mercury-2", providerID: "inception")
    ))

    let session = state.sessions[0]
    #expect(session.cost == 0.012)
    #expect(session.tokens.input == 1234)
    #expect(session.tokens.output == 56)
    #expect(session.tokens.reasoning == 7)
    #expect(session.model?.modelID == "mercury-2")
    #expect(session.model?.providerID == "inception")
}

@MainActor
@Test func sessionIdleClearsRunningAndStreamingFlags() async {
    let state = makeState()
    seedSession(state, sessionID: "ses_1")
    state.selectedSessionID = "ses_1"
    state.sendPrompt("anything")
    #expect(state.sessions[0].isRunning == true)

    state.apply(sessionIdle(sessionID: "ses_1"))

    #expect(state.sessions[0].isRunning == false)
    #expect(state.sessions[0].messages.allSatisfy { !$0.isStreaming })
}

@MainActor
@Test func toolPartActivityDetailShowsActionTaken() {
    let state = makeState()
    seedSession(state, sessionID: "ses_1")
    state.apply(messageUpdated(sessionID: "ses_1", messageID: "msg_a", role: "assistant"))

    // Tool part with a human-readable title: title wins.
    state.apply(toolPartUpdated(
        sessionID: "ses_1", messageID: "msg_a", partID: "prt_t1",
        tool: "bash", status: "running",
        stateJSON: #"{"status":"running","title":"swift test","input":{"command":"swift test"}}"#
    ))
    #expect(state.activity.first?.kind == .tool)
    #expect(state.activity.first?.title == "bash")
    #expect(state.activity.first?.detail == "swift test")

    // No title: fall back to rendering the input.
    state.apply(toolPartUpdated(
        sessionID: "ses_1", messageID: "msg_a", partID: "prt_t2",
        tool: "read", status: "completed",
        stateJSON: #"{"status":"completed","input":{"filePath":"/tmp/a.txt"}}"#
    ))
    #expect(state.activity.first?.title == "read")
    #expect(state.activity.first?.detail == "filePath: /tmp/a.txt")

    // No title or input: keep the old message-ID fallback.
    state.apply(toolPartUpdated(
        sessionID: "ses_1", messageID: "msg_a", partID: "prt_t3",
        tool: "task", status: "pending",
        stateJSON: #"{"status":"pending"}"#
    ))
    #expect(state.activity.first?.detail == "msg_a")
}

@MainActor
@Test func toolPartUpdatesTransitionInPlace() {
    let state = makeState()
    seedSession(state, sessionID: "ses_1")
    state.apply(messageUpdated(sessionID: "ses_1", messageID: "msg_a", role: "assistant"))

    // Same tool part streams running → completed: one row that transitions in place.
    state.apply(toolPartUpdated(
        sessionID: "ses_1", messageID: "msg_a", partID: "prt_t1",
        tool: "bash", status: "running",
        stateJSON: #"{"status":"running","title":"swift test"}"#
    ))
    let toolRows = { state.activity.filter { $0.kind == .tool } }
    #expect(toolRows().count == 1)
    #expect(state.activity.first?.state == "running")

    state.apply(toolPartUpdated(
        sessionID: "ses_1", messageID: "msg_a", partID: "prt_t1",
        tool: "bash", status: "completed",
        stateJSON: #"{"status":"completed","title":"swift test"}"#
    ))
    #expect(toolRows().count == 1)
    #expect(state.activity.first?.state == "completed")

    // A different part appends a new row rather than overwriting the first.
    state.apply(toolPartUpdated(
        sessionID: "ses_1", messageID: "msg_a", partID: "prt_t2",
        tool: "read", status: "running",
        stateJSON: #"{"status":"running","title":"read file"}"#
    ))
    #expect(toolRows().count == 2)
}

@MainActor
@Test func retryAssistantMessageRevertsToUserPromptAndResends() async throws {
    let state = makeState()
    seedSession(state, sessionID: "ses_1")
    state.selectedSessionID = "ses_1"
    state.sessions[0].messages = [
        TranscriptMessage(id: "msg_u", role: .user, parts: [TranscriptMessagePart(id: "p_u", type: "text", text: "hi")], date: Date(), isStreaming: false),
        TranscriptMessage(id: "msg_a", role: .assistant, parts: [TranscriptMessagePart(id: "p_a", type: "text", text: "Hello")], date: Date(), isStreaming: false)
    ]
    let mock = state.client!.networking as! RecordingNetworking
    mock.statusForPath = { $0.hasSuffix("/revert") ? 200 : nil }

    state.retryAssistantMessage("msg_a")
    try await waitForRequest(matching: { $0.url?.path == "/session/ses_1/prompt_async" }, in: mock)

    let revert = try #require(mock.requests.first { $0.url?.path == "/session/ses_1/revert" })
    let revertBody = try JSONSerialization.jsonObject(with: revert.httpBody ?? Data()) as? [String: Any]
    #expect(revertBody?["messageID"] as? String == "msg_u")

    let prompt = try #require(mock.requests.last { $0.url?.path == "/session/ses_1/prompt_async" })
    let promptBody = try JSONSerialization.jsonObject(with: prompt.httpBody ?? Data()) as? [String: Any]
    let parts = promptBody?["parts"] as? [[String: Any]]
    #expect(parts?.first?["text"] as? String == "hi")

    // Old turn removed; fresh local stubs in its place.
    let messages = state.sessions[0].messages
    #expect(messages.count == 2)
    #expect(messages[0].role == .user)
    #expect(messages[0].content == "hi")
    #expect(messages[0].id.hasPrefix("local-user-"))
    #expect(messages[1].role == .assistant)
}

@MainActor
@Test func editAndResendRevertsToMessageAndSendsNewText() async throws {
    let state = makeState()
    seedSession(state, sessionID: "ses_1")
    state.selectedSessionID = "ses_1"
    state.sessions[0].messages = [
        TranscriptMessage(id: "msg_u", role: .user, parts: [TranscriptMessagePart(id: "p_u", type: "text", text: "original")], date: Date(), isStreaming: false),
        TranscriptMessage(id: "msg_a", role: .assistant, parts: [TranscriptMessagePart(id: "p_a", type: "text", text: "reply")], date: Date(), isStreaming: false)
    ]
    let mock = state.client!.networking as! RecordingNetworking
    mock.statusForPath = { $0.hasSuffix("/revert") ? 200 : nil }

    state.editAndResend("msg_u", newText: "edited prompt")
    try await waitForRequest(matching: { $0.url?.path == "/session/ses_1/prompt_async" }, in: mock)

    let revert = try #require(mock.requests.first { $0.url?.path == "/session/ses_1/revert" })
    let revertBody = try JSONSerialization.jsonObject(with: revert.httpBody ?? Data()) as? [String: Any]
    #expect(revertBody?["messageID"] as? String == "msg_u")

    let prompt = try #require(mock.requests.last { $0.url?.path == "/session/ses_1/prompt_async" })
    let promptBody = try JSONSerialization.jsonObject(with: prompt.httpBody ?? Data()) as? [String: Any]
    let parts = promptBody?["parts"] as? [[String: Any]]
    #expect(parts?.first?["text"] as? String == "edited prompt")
    #expect(state.sessions[0].messages.first?.content == "edited prompt")
}

@MainActor
@Test func canRevertOnlyForServerMessagesWhileIdle() {
    let state = makeState()
    seedSession(state, sessionID: "ses_1")
    state.selectedSessionID = "ses_1"

    let serverMsg = TranscriptMessage(id: "msg_u", role: .user, parts: [], date: Date(), isStreaming: false)
    let localStub = TranscriptMessage(id: "local-user-x", role: .user, parts: [], date: Date(), isStreaming: false)
    let streaming = TranscriptMessage(id: "msg_a", role: .assistant, parts: [], date: Date(), isStreaming: true)

    #expect(state.canRevert(to: serverMsg) == true)
    #expect(state.canRevert(to: localStub) == false)
    #expect(state.canRevert(to: streaming) == false)

    state.sessions[0].isRunning = true
    #expect(state.canRevert(to: serverMsg) == false)
}

// MARK: - Helpers

@MainActor
private func makeState() -> AppState {
    let state = AppState()
    state.currentWorkspace = Workspace(path: "/tmp/workspace")
    let mock = RecordingNetworking()
    state.client = OpenCodeClient(
        baseURL: URL(string: "http://127.0.0.1:4096")!,
        directory: "/tmp/workspace",
        networking: mock
    )
    return state
}

@MainActor
private func seedSession(_ state: AppState, sessionID: String) {
    state.sessions = [
        OpenCodeSession(id: sessionID, title: "Test", createdAt: Date(), isRunning: false, messages: [])
    ]
}

@MainActor
private func waitForRequest(matching predicate: @escaping (URLRequest) -> Bool, in mock: RecordingNetworking, timeout seconds: Double = 3.0) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if mock.requests.contains(where: predicate) { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for matching request")
}

// MARK: - Event builders

private func decodeEvent(_ json: String) -> OpenCodeEvent {
    let data = json.data(using: .utf8)!
    return try! JSONDecoder().decode(OpenCodeEvent.self, from: data)
}

private func messageUpdated(sessionID: String, messageID: String, role: String) -> OpenCodeEvent {
    decodeEvent(#"""
    {
      "type": "message.updated",
      "properties": {
        "sessionID": "\#(sessionID)",
        "info": {
          "id": "\#(messageID)",
          "sessionID": "\#(sessionID)",
          "role": "\#(role)",
          "time": { "created": 1779918764975 }
        }
      }
    }
    """#)
}

private func messagePartUpdated(sessionID: String, messageID: String, partID: String, text: String) -> OpenCodeEvent {
    decodeEvent(#"""
    {
      "type": "message.part.updated",
      "properties": {
        "sessionID": "\#(sessionID)",
        "part": {
          "id": "\#(partID)",
          "type": "text",
          "text": "\#(text)",
          "messageID": "\#(messageID)",
          "sessionID": "\#(sessionID)"
        }
      }
    }
    """#)
}

private func messagePartDelta(sessionID: String, messageID: String, partID: String, delta: String) -> OpenCodeEvent {
    decodeEvent(#"""
    {
      "type": "message.part.delta",
      "properties": {
        "sessionID": "\#(sessionID)",
        "messageID": "\#(messageID)",
        "partID": "\#(partID)",
        "field": "text",
        "delta": "\#(delta)"
      }
    }
    """#)
}

private func toolPartUpdated(sessionID: String, messageID: String, partID: String, tool: String, status: String, stateJSON: String) -> OpenCodeEvent {
    decodeEvent(#"""
    {
      "type": "message.part.updated",
      "properties": {
        "sessionID": "\#(sessionID)",
        "part": {
          "id": "\#(partID)",
          "type": "tool",
          "tool": "\#(tool)",
          "messageID": "\#(messageID)",
          "sessionID": "\#(sessionID)",
          "state": \#(stateJSON)
        }
      }
    }
    """#)
}

private func sessionIdle(sessionID: String) -> OpenCodeEvent {
    decodeEvent(#"""
    {"type":"session.idle","properties":{"sessionID":"\#(sessionID)"}}
    """#)
}

private func sessionUpdated(sessionID: String, cost: Double, tokens: (input: Int, output: Int, reasoning: Int), model: (modelID: String, providerID: String)?) -> OpenCodeEvent {
    var modelJSON = "null"
    if let model {
        modelJSON = #"{"id":"\#(model.modelID)","providerID":"\#(model.providerID)"}"#
    }
    return decodeEvent(#"""
    {
      "type": "session.updated",
      "properties": {
        "info": {
          "id": "\#(sessionID)",
          "cost": \#(cost),
          "tokens": { "input": \#(tokens.input), "output": \#(tokens.output), "reasoning": \#(tokens.reasoning), "cache": { "read": 0, "write": 0 } },
          "model": \#(modelJSON)
        }
      }
    }
    """#)
}

// MARK: - Mock networking that records every request the client makes

final class RecordingNetworking: OpenCodeNetworking, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { _requests } }

    var nextResponseBody: Data = Data()
    var nextStatusCode: Int = 204
    // Optional per-request status override, keyed on the request URL path. Lets a test
    // mix endpoints with different success codes (e.g. revert=200, prompt=204).
    var statusForPath: (@Sendable (String) -> Int?)?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { _requests.append(request) }
        let code = statusForPath?(request.url?.path ?? "") ?? nextStatusCode
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: code,
            httpVersion: nil,
            headerFields: nil
        )!
        return (nextResponseBody, response)
    }
}
