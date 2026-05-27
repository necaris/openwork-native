import Foundation

protocol OpenCodeNetworking: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: OpenCodeNetworking {}

enum OpenCodeClientError: LocalizedError {
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "OpenCode returned an invalid response."
        case let .serverError(status, body):
            "OpenCode request failed (HTTP \(status)): \(body)"
        }
    }
}

struct OpenCodeClient: Sendable {
    var baseURL: URL
    var directory: String
    var networking: any OpenCodeNetworking

    init(baseURL: URL, directory: String, networking: any OpenCodeNetworking = URLSession.shared) {
        self.baseURL = baseURL
        self.directory = directory
        self.networking = networking
    }

    func health() async throws {
        _ = try await get(path: "/global/health", queryDirectory: false) as HealthResponse
    }

    func loadSessions() async throws -> [OpenCodeSession] {
        let sessions: [APISession] = try await get(path: "/session")
        return sessions.map(\.appModel)
    }

    func createSession(title: String = "New Session") async throws -> OpenCodeSession {
        let session: APISession = try await post(path: "/session", body: CreateSessionBody(title: title), expectedStatus: 200)
        return session.appModel
    }

    func loadMessages(sessionID: String) async throws -> [TranscriptMessage] {
        let envelopes: [APIMessageEnvelope] = try await get(path: "/session/\(sessionID)/message")
        return envelopes.map(\.appModel)
    }

    func sendPrompt(_ prompt: String, sessionID: String) async throws {
        let body = PromptBody(parts: [TextPartInput(text: prompt)])
        try await postNoBody(path: "/session/\(sessionID)/prompt_async", body: body, expectedStatus: 204)
    }

    func abort(sessionID: String) async throws {
        try await postNoBody(path: "/session/\(sessionID)/abort", body: EmptyBody(), expectedStatus: 200)
    }

    func replyPermission(sessionID: String, permissionID: String, decision: PermissionDecision) async throws {
        try await postNoBody(
            path: "/session/\(sessionID)/permissions/\(permissionID)",
            body: PermissionReplyBody(response: decision.rawValue),
            expectedStatus: 200
        )
    }

    func loadChangedFiles() async throws -> [ChangedFile] {
        let files: [APIChangedFile] = try await get(path: "/file/status")
        return files.map { ChangedFile(path: $0.path, status: $0.status) }
    }

    func loadProviders() async throws -> [ModelProvider] {
        let response: ProviderListResponse = try await get(path: "/provider")
        return response.all.map { provider in
            let models = provider.models.keys.sorted()
            let selected = response.default[provider.id] ?? models.first ?? "No configured model"
            let status = response.connected.contains(provider.id) ? "Connected" : "Not connected"
            return ModelProvider(name: provider.name, models: models.isEmpty ? [selected] : models, selectedModel: selected, authStatus: status)
        }
    }

    func makeEventRequest() -> URLRequest {
        request(path: "/event", method: "GET")
    }

    private func get<T: Decodable>(path: String, queryDirectory: Bool = true) async throws -> T {
        let request = request(path: path, method: "GET", queryDirectory: queryDirectory)
        let data = try await responseData(for: request, expectedStatus: 200)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Encodable, U: Decodable>(path: String, body: T, expectedStatus: Int) async throws -> U {
        var request = request(path: path, method: "POST")
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try await responseData(for: request, expectedStatus: expectedStatus)
        return try JSONDecoder().decode(U.self, from: data)
    }

    private func postNoBody<T: Encodable>(path: String, body: T, expectedStatus: Int) async throws {
        var request = request(path: path, method: "POST")
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await responseData(for: request, expectedStatus: expectedStatus)
    }

    private func request(path: String, method: String, queryDirectory: Bool = true) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        if queryDirectory {
            components.queryItems = [URLQueryItem(name: "directory", value: directory)]
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func responseData(for request: URLRequest, expectedStatus: Int) async throws -> Data {
        let method = request.httpMethod ?? "GET"
        let urlString = request.url?.absoluteString ?? "<nil>"
        AppLog.client.debug("\(method, privacy: .public) \(urlString, privacy: .public)")
        do {
            let (data, response) = try await networking.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                AppLog.client.error("\(method, privacy: .public) \(urlString, privacy: .public) — non-HTTP response")
                throw OpenCodeClientError.invalidResponse
            }
            guard httpResponse.statusCode == expectedStatus else {
                let body = String(data: data, encoding: .utf8) ?? ""
                AppLog.client.error("\(method, privacy: .public) \(urlString, privacy: .public) — HTTP \(httpResponse.statusCode, privacy: .public) body=\(body, privacy: .public)")
                throw OpenCodeClientError.serverError(httpResponse.statusCode, body)
            }
            AppLog.client.debug("\(method, privacy: .public) \(urlString, privacy: .public) — HTTP \(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public)")
            return data
        } catch {
            AppLog.client.error("\(method, privacy: .public) \(urlString, privacy: .public) — transport error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}

struct OpenCodeEvent: Decodable, Equatable {
    let type: String
    let properties: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        properties = (try? container.decode([String: JSONValue].self, forKey: .properties)) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case properties
    }
}

extension OpenCodeEvent {
    var sessionID: String? {
        if let direct = properties["sessionID"]?.stringValue { return direct }
        return properties["info"]?.objectValue?["sessionID"]?.stringValue
            ?? properties["info"]?.objectValue?["id"]?.stringValue
            ?? properties["part"]?.objectValue?["sessionID"]?.stringValue
    }

    var messageID: String? {
        properties["messageID"]?.stringValue
            ?? properties["info"]?.objectValue?["id"]?.stringValue
            ?? properties["part"]?.objectValue?["messageID"]?.stringValue
    }

    var partID: String? {
        properties["part"]?.objectValue?["id"]?.stringValue
    }

    var partType: String? {
        properties["part"]?.objectValue?["type"]?.stringValue
    }

    var textDelta: String? {
        properties["delta"]?.stringValue
    }

    var partText: String? {
        properties["part"]?.objectValue?["text"]?.stringValue
    }

    var sessionStatus: String? {
        properties["status"]?.objectValue?["type"]?.stringValue
    }

    var permissionRequest: PermissionRequest? {
        guard type == "permission.asked" else { return nil }
        let id = properties["id"]?.stringValue ?? UUID().uuidString
        let sessionID = properties["sessionID"]?.stringValue ?? ""
        let action = properties["permission"]?.stringValue
            ?? properties["title"]?.stringValue
            ?? "Permission requested"
        let target: String
        if let patterns = properties["patterns"]?.arrayValue {
            target = patterns.compactMap(\.stringValue).joined(separator: ", ")
        } else {
            target = properties["pattern"]?.displayValue ?? ""
        }
        let metadata = properties["metadata"]?.displayValue
        return PermissionRequest(
            id: id,
            sessionID: sessionID,
            sessionTitle: sessionID,
            action: action,
            target: target,
            reason: (metadata?.isEmpty == false) ? metadata! : "OpenCode requested permission for this action."
        )
    }

    var todos: [ActivityItem]? {
        guard type == "todo.updated", let values = properties["todos"]?.arrayValue else { return nil }
        return values.compactMap { value in
            guard let todo = value.objectValue else { return nil }
            let content = todo["content"]?.stringValue ?? "Todo"
            let status = todo["status"]?.stringValue ?? "pending"
            let priority = todo["priority"]?.stringValue ?? ""
            return ActivityItem(id: UUID(), kind: .todo, title: content, detail: priority, state: status)
        }
    }
}

private struct HealthResponse: Decodable {
    let healthy: Bool
    let version: String?
}

private struct CreateSessionBody: Encodable {
    let title: String
}

private struct EmptyBody: Encodable {}

private struct PermissionReplyBody: Encodable {
    let response: String
}

private struct PromptBody: Encodable {
    let parts: [TextPartInput]
}

private struct TextPartInput: Encodable {
    let type = "text"
    let text: String
}

private struct APISession: Decodable {
    struct Time: Decodable {
        let created: Double
    }

    let id: String
    let title: String
    let time: Time?

    var appModel: OpenCodeSession {
        OpenCodeSession(
            id: id,
            title: title,
            createdAt: Date(timeIntervalSince1970: (time?.created ?? 0) / 1000),
            isRunning: false,
            messages: []
        )
    }
}

private struct APIMessageEnvelope: Decodable {
    let info: APIMessageInfo
    let parts: [APIMessagePart]

    var appModel: TranscriptMessage {
        let content = parts
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
        let thinking = parts
            .filter { $0.type == "reasoning" }
            .compactMap(\.text)
            .joined(separator: "\n")
        return TranscriptMessage(
            id: info.id,
            role: info.role == "assistant" ? .assistant : .user,
            content: content,
            date: Date(timeIntervalSince1970: (info.time?.created ?? 0) / 1000),
            isStreaming: false,
            thinking: thinking.isEmpty ? nil : thinking
        )
    }
}

private struct APIMessageInfo: Decodable {
    struct Time: Decodable {
        let created: Double
    }

    let id: String
    let role: String
    let time: Time?
}

private struct APIMessagePart: Decodable {
    let type: String
    let text: String?
}

private struct APIChangedFile: Decodable {
    let path: String
    let status: String
}

private struct ProviderListResponse: Decodable {
    let all: [APIProvider]
    let `default`: [String: String]
    let connected: [String]
}

private struct APIProvider: Decodable {
    let id: String
    let name: String
    let models: [String: APIProviderModel]
}

private struct APIProviderModel: Decodable {}
