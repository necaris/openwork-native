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
        parts.filter { $0.type == "text" || $0.type == "tool_call" || $0.type == "tool_result" }.map { part in
            if part.type == "tool_call" {
                return "\n> **Tool Call:** `\(part.text.split(separator: "\n").first ?? "unknown")`\n"
            } else if part.type == "tool_result" {
                return "\n<details>\n<summary>Tool Result</summary>\n\n```\n\(part.text)\n```\n</details>\n"
            }
            return part.text
        }.joined(separator: "\n")
    }

    var thinking: String? {
        let t = parts.filter { $0.type == "reasoning" }.map(\.text).joined(separator: "\n")
        return t.isEmpty ? nil : t
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

struct ModelProvider: Identifiable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var models: [String]
    var selectedModel: String
    var authStatus: String
}

enum WorkspaceInventoryKind: String, CaseIterable, Sendable {
    case skill = "Skills"
    case command = "Commands"
    case plugin = "Plugins"
    case mcp = "MCP"
}

struct WorkspaceInventoryItem: Identifiable, Equatable, Sendable {
    var id: String { "\(kind.rawValue):\(name):\(path)" }
    var kind: WorkspaceInventoryKind
    var name: String
    var path: String
    var detail: String

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
