import Foundation
import Testing
@testable import OpenWorkNative

@Test func loadSessionsUsesOpenCodeIDsAndDirectoryQuery() async throws {
    let networking = MockNetworking(data: #"""
    [
      {
        "id": "ses_123",
        "title": "Real Session",
        "time": { "created": 1710000000000 }
      }
    ]
    """#.data(using: .utf8)!)
    let client = OpenCodeClient(
        baseURL: URL(string: "http://127.0.0.1:4096")!,
        directory: "/tmp/workspace",
        networking: networking
    )

    let sessions = try await client.loadSessions()

    #expect(sessions.first?.id == "ses_123")
    #expect(sessions.first?.title == "Real Session")
    #expect(networking.lastRequest?.url?.path == "/session")
    #expect(URLComponents(url: networking.lastRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "/tmp/workspace")
}

@Test func loadMessagesMapsTextAndReasoningParts() async throws {
    let networking = MockNetworking(data: #"""
    [
      {
        "info": { "id": "msg_1", "role": "assistant", "time": { "created": 1710000000000 } },
        "parts": [
          { "type": "reasoning", "text": "Thinking" },
          { "type": "text", "text": "Answer" }
        ]
      }
    ]
    """#.data(using: .utf8)!)
    let client = OpenCodeClient(
        baseURL: URL(string: "http://127.0.0.1:4096")!,
        directory: "/tmp/workspace",
        networking: networking
    )

    let messages = try await client.loadMessages(sessionID: "ses_123")

    #expect(messages.first?.id == "msg_1")
    #expect(messages.first?.role == .assistant)
    #expect(messages.first?.content == "Answer")
    #expect(messages.first?.thinking == "Thinking")
}

private final class MockNetworking: OpenCodeNetworking, @unchecked Sendable {
    let data: Data
    private(set) var lastRequest: URLRequest?

    init(data: Data) {
        self.data = data
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
