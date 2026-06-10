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

@Test func loadMessagesMapsToolPartsAndErrorNameFallback() async throws {
    let networking = MockNetworking(data: #"""
    [
      {
        "info": {
          "id": "msg_tool",
          "role": "assistant",
          "time": { "created": 1710000000000, "completed": 1710000001250 },
          "error": { "name": "ToolError" }
        },
        "parts": [
          { "id": "call_1", "type": "tool_call", "toolCall": { "name": "bash" } },
          { "id": "result_1", "type": "tool_result", "toolResult": { "text": null } }
        ]
      }
    ]
    """#.data(using: .utf8)!)
    let client = makeClient(networking: networking)

    let message = try #require(try await client.loadMessages(sessionID: "ses_123").first)

    #expect(message.id == "msg_tool")
    #expect(message.parts == [
        TranscriptMessagePart(id: "call_1", type: "tool_call", text: "bash"),
        TranscriptMessagePart(id: "result_1", type: "tool_result", text: "No output")
    ])
    #expect(message.errorMessage == "ToolError")
    #expect(message.latency == 1.25)
}

@Test func healthUsesGlobalRouteWithoutDirectoryQuery() async throws {
    let networking = MockNetworking(data: #"""
    { "healthy": true, "version": "1.15.10" }
    """#.data(using: .utf8)!)
    let client = makeClient(networking: networking)

    try await client.health()

    #expect(networking.lastRequest?.httpMethod == "GET")
    #expect(networking.lastRequest?.url?.path == "/global/health")
    #expect(URLComponents(url: networking.lastRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems == nil)
}

@Test func createSessionPostsTitleAndDecodesResponse() async throws {
    let networking = MockNetworking(data: #"""
    {
      "id": "ses_new",
      "title": "Plan ship",
      "time": { "created": 1710000000000 }
    }
    """#.data(using: .utf8)!)
    let client = makeClient(networking: networking)

    let session = try await client.createSession(title: "Plan ship")

    #expect(session.id == "ses_new")
    #expect(session.title == "Plan ship")
    #expect(networking.lastRequest?.httpMethod == "POST")
    #expect(networking.lastRequest?.url?.path == "/session")
    #expect(networking.lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let body = try #require(try networking.jsonBody())
    #expect(body["title"] as? String == "Plan ship")
}

@Test func sendPromptPostsPromptAsyncBodyAndRequiresNoContentStatus() async throws {
    let networking = MockNetworking(data: Data(), statusCode: 204)
    let client = makeClient(networking: networking)

    try await client.sendPrompt("Fix the parser", sessionID: "ses_123")

    #expect(networking.lastRequest?.httpMethod == "POST")
    #expect(networking.lastRequest?.url?.path == "/session/ses_123/prompt_async")
    let body = try #require(try networking.jsonBody())
    let parts = try #require(body["parts"] as? [[String: Any]])
    #expect(parts.count == 1)
    #expect(parts.first?["type"] as? String == "text")
    #expect(parts.first?["text"] as? String == "Fix the parser")
}

@Test func sendPromptCanIncludeSessionModelOverride() async throws {
    let networking = MockNetworking(data: Data(), statusCode: 204)
    let client = makeClient(networking: networking)

    try await client.sendPrompt(
        "Use this model",
        sessionID: "ses_123",
        model: SessionModel(modelID: "claude-3-5-sonnet", providerID: "anthropic")
    )

    let body = try #require(try networking.jsonBody())
    let model = try #require(body["model"] as? [String: Any])
    #expect(model["providerID"] as? String == "anthropic")
    #expect(model["modelID"] as? String == "claude-3-5-sonnet")
}

@Test func abortPostsToSessionAbortRoute() async throws {
    let networking = MockNetworking(data: Data(), statusCode: 200)
    let client = makeClient(networking: networking)

    try await client.abort(sessionID: "ses_123")

    #expect(networking.lastRequest?.httpMethod == "POST")
    #expect(networking.lastRequest?.url?.path == "/session/ses_123/abort")
}

@Test func replyPermissionPostsDecisionBody() async throws {
    let networking = MockNetworking(data: Data(), statusCode: 200)
    let client = makeClient(networking: networking)

    try await client.replyPermission(sessionID: "ses_123", permissionID: "perm_1", decision: .always)

    #expect(networking.lastRequest?.httpMethod == "POST")
    #expect(networking.lastRequest?.url?.path == "/session/ses_123/permissions/perm_1")
    let body = try #require(try networking.jsonBody())
    #expect(body["response"] as? String == "always")
}

@Test func loadChangedFilesMapsFileStatus() async throws {
    let networking = MockNetworking(data: #"""
    [
      { "path": "Sources/App.swift", "status": "modified" },
      { "path": "README.md", "status": "added" }
    ]
    """#.data(using: .utf8)!)
    let client = makeClient(networking: networking)

    let files = try await client.loadChangedFiles()

    #expect(files == [
        ChangedFile(path: "Sources/App.swift", status: "modified"),
        ChangedFile(path: "README.md", status: "added")
    ])
    #expect(networking.lastRequest?.url?.path == "/file/status")
}

@Test func loadProvidersMapsDefaultsSortedModelsAndConnectionStatus() async throws {
    let networking = MockNetworking(data: #"""
    {
      "all": [
        {
          "id": "anthropic",
          "name": "Anthropic",
          "models": {
            "claude-3-5-sonnet": {},
            "claude-3-opus": {}
          }
        },
        {
          "id": "local",
          "name": "Local",
          "models": {}
        }
      ],
      "default": {
        "anthropic": "claude-3-5-sonnet",
        "local": "No configured model"
      },
      "connected": ["anthropic"]
    }
    """#.data(using: .utf8)!)
    let client = makeClient(networking: networking)

    let providers = try await client.loadProviders()

    #expect(providers.count == 2)
    #expect(providers[0].id == "anthropic")
    #expect(providers[0].name == "Anthropic")
    #expect(providers[0].models == ["claude-3-5-sonnet", "claude-3-opus"])
    #expect(providers[0].modelIDs == ["anthropic/claude-3-5-sonnet", "anthropic/claude-3-opus"])
    #expect(providers[0].selectedModel == "claude-3-5-sonnet")
    #expect(providers[0].authStatus == "Connected")
    #expect(providers[1].models == ["No configured model"])
    #expect(providers[1].modelIDs == [])
    #expect(providers[1].authStatus == "Not connected")
}

@Test func loadConfigReadsCurrentDefaultModel() async throws {
    let networking = MockNetworking(data: #"{"model":"anthropic/claude-3-5-sonnet"}"#.data(using: .utf8)!)
    let client = makeClient(networking: networking)

    let config = try await client.loadConfig()

    #expect(config.model == "anthropic/claude-3-5-sonnet")
    #expect(networking.lastRequest?.httpMethod == "GET")
    #expect(networking.lastRequest?.url?.path == "/config")
}

@Test func updateDefaultModelPatchesConfigModel() async throws {
    let networking = MockNetworking(data: #"{"model":"anthropic/claude-opus-4-1"}"#.data(using: .utf8)!)
    let client = makeClient(networking: networking)

    let selected = try await client.updateDefaultModel("anthropic/claude-opus-4-1")

    #expect(selected == "anthropic/claude-opus-4-1")
    #expect(networking.lastRequest?.httpMethod == "PATCH")
    #expect(networking.lastRequest?.url?.path == "/global/config")
    #expect(URLComponents(url: networking.lastRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems == nil)
    #expect(networking.lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let body = try #require(try networking.jsonBody())
    #expect(body["model"] as? String == "anthropic/claude-opus-4-1")
}

@Test func makeEventRequestSetsSSEHeaders() {
    let client = makeClient(networking: MockNetworking(data: Data()))

    let request = client.makeEventRequest()

    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/event")
    #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-cache")
    #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "/tmp/workspace")
}

@Test func serverErrorIncludesStatusAndBody() async throws {
    let networking = MockNetworking(data: Data("not found".utf8), statusCode: 404)
    let client = makeClient(networking: networking)

    do {
        try await client.health()
        Issue.record("Expected server error")
    } catch let error as OpenCodeClientError {
        guard case let .serverError(status, body) = error else {
            Issue.record("Expected serverError, got \(error)")
            return
        }
        #expect(status == 404)
        #expect(body == "not found")
    }
}

@Test func invalidResponseThrowsClientError() async throws {
    let networking = MockNetworking(
        data: Data(),
        response: URLResponse(
            url: URL(string: "http://127.0.0.1:4096/global/health")!,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )
    )
    let client = makeClient(networking: networking)

    do {
        try await client.health()
        Issue.record("Expected invalid response error")
    } catch let error as OpenCodeClientError {
        guard case .invalidResponse = error else {
            Issue.record("Expected invalidResponse, got \(error)")
            return
        }
    }
}

private func makeClient(networking: MockNetworking) -> OpenCodeClient {
    OpenCodeClient(
        baseURL: URL(string: "http://127.0.0.1:4096")!,
        directory: "/tmp/workspace",
        networking: networking
    )
}

private final class MockNetworking: OpenCodeNetworking, @unchecked Sendable {
    let data: Data
    let statusCode: Int
    let response: URLResponse?
    private(set) var lastRequest: URLRequest?

    init(data: Data, statusCode: Int = 200, response: URLResponse? = nil) {
        self.data = data
        self.statusCode = statusCode
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let response {
            return (data, response)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func jsonBody() throws -> [String: Any]? {
        guard let httpBody = lastRequest?.httpBody else { return nil }
        return try JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
    }
}
