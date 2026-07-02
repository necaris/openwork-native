import Foundation

struct Workspace: Identifiable, Codable, Equatable, Sendable {
    var id: String { path }
    let path: String
    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

enum RuntimeStatus: String, Equatable, Sendable {
    case stopped = "Stopped"
    case starting = "Starting"
    case running = "Running"
    case failed = "Failed"
}

struct TokenUsage: Equatable, Sendable {
    var input: Int = 0
    var output: Int = 0
    var reasoning: Int = 0
    var cacheRead: Int = 0
    var cacheWrite: Int = 0

    var total: Int { input + output + reasoning }
}

struct SessionModel: Equatable, Sendable {
    var modelID: String
    var providerID: String
}

struct OpenCodeSession: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var createdAt: Date
    var isRunning: Bool
    var messages: [TranscriptMessage]
    var cost: Double = 0
    var tokens: TokenUsage = TokenUsage()
    var model: SessionModel?
}

struct TranscriptMessagePart: Identifiable, Equatable, Sendable {
    let id: String
    let type: String
    var text: String

    /// Renders a "tool" part (OpenCode's real part type — there is no separate
    /// tool-call/tool-result pair) as inline markdown, so a tool-only assistant
    /// turn still shows something instead of an empty bubble.
    static func toolCallText(tool: String, title: String?, status: String?, output: String?) -> String {
        var header = "> **Tool:** `\(tool)`"
        if let title, !title.isEmpty, title != tool {
            header += " — \(title)"
        }
        if let status, !status.isEmpty, status != "completed" {
            header += " _(\(status))_"
        }
        guard let output, !output.isEmpty else { return header }
        return header + "\n\n<details>\n<summary>Output</summary>\n\n```\n\(output)\n```\n</details>"
    }
}

struct TranscriptMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable {
        case user = "User"
        case assistant = "Assistant"
        case system = "System"
    }

    let id: String
    var role: Role
    var parts: [TranscriptMessagePart]
    var date: Date
    var isStreaming: Bool
    var model: SessionModel?
    var tokens: TokenUsage?
    var cost: Double?
    var latency: TimeInterval?
    var errorMessage: String?

    var content: String {
        parts.filter { $0.type == "text" || $0.type == "tool" }.map(\.text).joined(separator: "\n")
    }

    var thinking: String? {
        let t = parts.filter { $0.type == "reasoning" }.map(\.text).joined(separator: "\n")
        return t.isEmpty ? nil : t
    }

    /// True for an assistant turn made up entirely of tool calls, with no
    /// accompanying text response — these collapse to a slim summary by default.
    var isToolCallOnly: Bool {
        guard role == .assistant else { return false }
        let hasToolPart = parts.contains { $0.type == "tool" }
        let hasText = parts.contains { $0.type == "text" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return hasToolPart && !hasText
    }

    var toolCallCount: Int {
        parts.filter { $0.type == "tool" }.count
    }
}

struct ActivityItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case step = "Step"
        case tool = "Tool"
        case todo = "Todo"
        case file = "File"
        case runtime = "Runtime"
    }

    let id: UUID
    var kind: Kind
    var title: String
    var detail: String
    var state: String
    // Stable identity for live rows that transition in place (e.g. a tool part's
    // ID across running → completed/failed). Nil for one-shot rows that always append.
    var sourceID: String? = nil
    // The transcript message this row was derived from, if any — lets the sidebar
    // scroll to and expand the originating message when a row is clicked.
    var messageID: String? = nil
}

struct PermissionRequest: Identifiable, Equatable, Sendable {
    let id: String
    var sessionID: String
    var sessionTitle: String
    var action: String
    var target: String
    var reason: String
}

struct ChangedFile: Identifiable, Equatable, Sendable {
    var id: String { path }
    var path: String
    var status: String
}

struct ModelCapability: Equatable, Sendable {
    var reasoning: Bool
    var outputText: Bool
    var outputImage: Bool
}

struct ModelProvider: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var models: [String]
    var selectedModel: String
    var authStatus: String
    var modelCapabilities: [String: ModelCapability] = [:]

    var modelIDs: [String] {
        models
            .filter { $0 != "No configured model" }
            .map { "\(id)/\($0)" }
    }
}

enum WorkspaceInventoryKind: String, CaseIterable, Sendable {
    case skill = "Skills"
    case command = "Commands"
    case plugin = "Plugins"
    case mcp = "MCP"

    var sortOrder: Int {
        switch self {
        case .skill: 0
        case .command: 1
        case .plugin: 2
        case .mcp: 3
        }
    }
}

struct WorkspaceInventoryItem: Identifiable, Equatable, Sendable {
    var id: String { "\(kind.rawValue):\(name):\(path)" }
    var kind: WorkspaceInventoryKind
    var name: String
    var path: String
    var detail: String
    var status: String? = nil
    var statusDetail: String? = nil

    var slashCommand: String? {
        guard kind == .command || kind == .skill else { return nil }
        return "/\(name)"
    }
}

enum PermissionDecision: String, Sendable {
    case once
    case always
    case reject

    var displayName: String {
        switch self {
        case .once: "allowed once"
        case .always: "always allowed"
        case .reject: "denied"
        }
    }
}

enum JSONValue: Decodable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case let .number(value) = self { return Int(value) }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    var displayValue: String {
        switch self {
        case let .string(value): value
        case let .number(value): String(value)
        case let .bool(value): String(value)
        case let .object(value): value.map { "\($0.key): \($0.value.displayValue)" }.sorted().joined(separator: ", ")
        case let .array(value): value.map(\.displayValue).joined(separator: ", ")
        case .null: ""
        }
    }
}
