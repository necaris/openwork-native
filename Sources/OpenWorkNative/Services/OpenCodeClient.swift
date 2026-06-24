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

    func sendPrompt(_ prompt: String, sessionID: String, model: SessionModel? = nil) async throws {
        let body = PromptBody(model: model.map(ModelPartInput.init), parts: [TextPartInput(text: prompt)])
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
            return ModelProvider(id: provider.id, name: provider.name, models: models.isEmpty ? [selected] : models, selectedModel: selected, authStatus: status)
        }
    }

    func loadConfig() async throws -> OpenCodeConfig {
        try await get(path: "/config")
    }

    /// Builds the inventory from the server's resolved view (GET /skill, /command,
    /// /mcp, /config) instead of re-reading config files, so overlapping config
    /// sources never produce duplicate entries and MCP rows carry live status.
    func loadInventory() async throws -> [WorkspaceInventoryItem] {
        async let skillsRequest: [APISkill] = get(path: "/skill")
        async let commandsRequest: [APICommand] = get(path: "/command")
        async let mcpRequest: [String: APIMCPStatus] = get(path: "/mcp")
        async let configRequest: OpenCodeConfig = get(path: "/config")
        let (skills, commands, mcpStatuses, config) = try await (skillsRequest, commandsRequest, mcpRequest, configRequest)

        var items: [WorkspaceInventoryItem] = []

        items.append(contentsOf: skills.map { skill in
            WorkspaceInventoryItem(
                kind: .skill,
                name: skill.name,
                path: (skill.location?.hasPrefix("/") == true) ? skill.location! : "",
                detail: skill.description ?? ""
            )
        })

        // GET /command mirrors every skill as a command; keep only real commands
        // so skills do not show up twice across sections.
        items.append(contentsOf: commands.filter { ($0.source ?? "command") == "command" }.map { command in
            WorkspaceInventoryItem(
                kind: .command,
                name: command.name,
                path: "",
                detail: command.description ?? ""
            )
        })

        let configMCP = config.mcp ?? [:]
        let mcpNames = Set(mcpStatuses.keys).union(configMCP.keys)
        items.append(contentsOf: mcpNames.map { name in
            WorkspaceInventoryItem(
                kind: .mcp,
                name: name,
                path: "",
                detail: Self.mcpDetail(configMCP[name]),
                status: mcpStatuses[name]?.status,
                statusDetail: mcpStatuses[name]?.error
            )
        })

        items.append(contentsOf: (config.plugin ?? []).compactMap(\.stringValue).map { plugin in
            WorkspaceInventoryItem(kind: .plugin, name: plugin, path: "", detail: "")
        })

        return items.sorted {
            if $0.kind == $1.kind {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.kind.sortOrder < $1.kind.sortOrder
        }
    }

    private static func mcpDetail(_ value: JSONValue?) -> String {
        guard let object = value?.objectValue else { return "" }
        var parts: [String] = []
        if let type = object["type"]?.stringValue, !type.isEmpty {
            parts.append("type: \(type)")
        }
        if let command = object["command"] {
            let words = command.arrayValue?.compactMap(\.stringValue) ?? command.stringValue.map { [$0] } ?? []
            if !words.isEmpty {
                parts.append("command: \(words.joined(separator: " "))")
            }
        } else if let url = object["url"]?.stringValue {
            parts.append("url: \(url)")
        }
        if object["enabled"] == .bool(false) {
            parts.append("disabled")
        }
        return parts.joined(separator: " · ")
    }

    func updateDefaultModel(_ modelID: String) async throws -> String? {
        // PATCH /config writes a workspace config.json that current OpenCode builds do not
        // reread through GET /config. The global config API updates the effective model.
        let config: OpenCodeConfig = try await patch(path: "/global/config", body: UpdateConfigBody(model: modelID), expectedStatus: 200, queryDirectory: false)
        return config.model
    }

    func makeEventRequest() -> URLRequest {
        var request = self.request(path: "/event", method: "GET")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
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

    private func patch<T: Encodable, U: Decodable>(path: String, body: T, expectedStatus: Int, queryDirectory: Bool = true) async throws -> U {
        var request = request(path: path, method: "PATCH", queryDirectory: queryDirectory)
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try await responseData(for: request, expectedStatus: expectedStatus)
        return try JSONDecoder().decode(U.self, from: data)
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

    // Extracts a human-readable message from a `session.error` event. OpenCode nests
    // the detail under error.data.message (e.g. "Bad Request: Model must be one of…"),
    // falling back to error.message, the error name, or a flattened rendering.
    var sessionErrorMessage: String {
        guard let error = properties["error"] else { return "Unknown error" }
        if let text = error.stringValue, !text.isEmpty { return text }
        if let object = error.objectValue {
            if let message = object["data"]?.objectValue?["message"]?.stringValue, !message.isEmpty {
                return message
            }
            if let message = object["message"]?.stringValue, !message.isEmpty {
                return message
            }
            if let name = object["name"]?.stringValue, !name.isEmpty {
                return name
            }
        }
        let rendered = error.displayValue
        return rendered.isEmpty ? "Unknown error" : rendered
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
    let model: ModelPartInput?
    let parts: [TextPartInput]
}

private struct ModelPartInput: Encodable {
    let providerID: String
    let modelID: String

    init(_ model: SessionModel) {
        providerID = model.providerID
        modelID = model.modelID
    }
}

struct OpenCodeConfig: Decodable, Equatable, Sendable {
    let model: String?
    let mcp: [String: JSONValue]?
    let plugin: [JSONValue]?

    init(model: String?, mcp: [String: JSONValue]? = nil, plugin: [JSONValue]? = nil) {
        self.model = model
        self.mcp = mcp
        self.plugin = plugin
    }
}

struct APISkill: Decodable, Equatable, Sendable {
    let name: String
    let description: String?
    let location: String?
}

struct APICommand: Decodable, Equatable, Sendable {
    let name: String
    let description: String?
    let source: String?
}

struct APIMCPStatus: Decodable, Equatable, Sendable {
    let status: String
    let error: String?
}

private struct UpdateConfigBody: Encodable {
    let model: String
}

private struct TextPartInput: Encodable {
    let type = "text"
    let text: String
}

struct APITokens: Decodable, Equatable, Sendable {
    struct Cache: Decodable, Equatable, Sendable {
        let read: Int?
        let write: Int?
    }

    let input: Int?
    let output: Int?
    let reasoning: Int?
    let cache: Cache?

    var appModel: TokenUsage {
        TokenUsage(
            input: input ?? 0,
            output: output ?? 0,
            reasoning: reasoning ?? 0,
            cacheRead: cache?.read ?? 0,
            cacheWrite: cache?.write ?? 0
        )
    }
}

struct APISessionModel: Decodable, Equatable, Sendable {
    let id: String?
    let modelID: String?
    let providerID: String?

    var appModel: SessionModel? {
        let resolvedID = modelID ?? id
        guard let modelID = resolvedID, let providerID else { return nil }
        return SessionModel(modelID: modelID, providerID: providerID)
    }
}

struct APISession: Decodable {
    struct Time: Decodable {
        let created: Double
        let updated: Double?
    }

    let id: String
    let title: String
    let time: Time?
    let cost: Double?
    let tokens: APITokens?
    let model: APISessionModel?

    var appModel: OpenCodeSession {
        OpenCodeSession(
            id: id,
            title: title,
            createdAt: Date(timeIntervalSince1970: (time?.created ?? 0) / 1000),
            isRunning: false,
            messages: [],
            cost: cost ?? 0,
            tokens: tokens?.appModel ?? TokenUsage(),
            model: model?.appModel
        )
    }
}

struct APIMessageEnvelope: Decodable {
    let info: APIMessageInfo
    let parts: [APIMessagePart]

    var appModel: TranscriptMessage {
        let created = (info.time?.created ?? 0) / 1000
        let completed = (info.time?.completed ?? 0) / 1000
        let latency: TimeInterval? = (info.time?.completed != nil && info.time?.created != nil)
            ? max(0, completed - created)
            : nil
            
        let mappedParts = parts.map { part -> TranscriptMessagePart in
            var text = part.text ?? ""
            if part.type == "tool_call" {
                text = part.toolCall?.name ?? "tool"
            } else if part.type == "tool_result" {
                text = part.toolResult?.text ?? "No output"
            }
            return TranscriptMessagePart(id: part.id ?? UUID().uuidString, type: part.type, text: text)
        }
            
        return TranscriptMessage(
            id: info.id,
            role: info.role == "assistant" ? .assistant : .user,
            parts: mappedParts,
            date: Date(timeIntervalSince1970: created),
            isStreaming: false,
            model: info.resolvedModel,
            tokens: info.tokens?.appModel,
            cost: info.cost,
            latency: latency,
            errorMessage: info.error?.message
        )
    }
}

struct APIMessageInfo: Decodable {
    struct Time: Decodable {
        let created: Double?
        let completed: Double?
    }

    struct APIError: Decodable {
        struct Data: Decodable {
            let message: String?
        }
        let name: String?
        let data: Data?

        var message: String? {
            if let inner = data?.message, !inner.isEmpty { return inner }
            return name
        }
    }

    let id: String
    let role: String
    let time: Time?
    let cost: Double?
    let tokens: APITokens?

    // Assistant info uses flat fields; user info nests these under "model".
    let modelID: String?
    let providerID: String?
    let model: APISessionModel?

    let error: APIError?

    var resolvedModel: SessionModel? {
        if let nested = model?.appModel { return nested }
        if let modelID, let providerID {
            return SessionModel(modelID: modelID, providerID: providerID)
        }
        return nil
    }
}

struct APIMessagePart: Decodable {
    let id: String?
    let type: String
    let text: String?
    let toolCall: APIToolCall?
    let toolResult: APIToolResult?
    
    struct APIToolCall: Decodable {
        let name: String
    }
    
    struct APIToolResult: Decodable {
        let text: String?
    }
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
