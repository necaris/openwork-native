import Foundation
import XCTest
@testable import OpenWorkNative

final class OpenCodeClientTests: XCTestCase {
    func testLoadSessionsUsesOpenCodeIDsAndDirectoryQuery() async throws {
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

        XCTAssertEqual(sessions.first?.id, "ses_123")
        XCTAssertEqual(sessions.first?.title, "Real Session")
        XCTAssertEqual(networking.lastRequest?.url?.path, "/session")
        XCTAssertEqual(URLComponents(url: networking.lastRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "/tmp/workspace")
    }

    func testLoadMessagesMapsTextAndReasoningParts() async throws {
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

        XCTAssertEqual(messages.first?.id, "msg_1")
        XCTAssertEqual(messages.first?.role, .assistant)
        XCTAssertEqual(messages.first?.content, "Answer")
        XCTAssertEqual(messages.first?.thinking, "Thinking")
    }
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
