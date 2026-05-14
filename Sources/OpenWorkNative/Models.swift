import Foundation

struct Workspace: Identifiable, Codable, Equatable {
    var id: String { path }
    let path: String
    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

enum RuntimeStatus: String, Equatable {
    case stopped = "Stopped"
    case starting = "Starting"
    case running = "Running"
    case failed = "Failed"
}

struct OpenCodeSession: Identifiable, Equatable {
    let id: String
    var title: String
    var createdAt: Date
    var isRunning: Bool
    var messages: [TranscriptMessage]
}

struct TranscriptMessage: Identifiable, Equatable {
    enum Role: String {
        case user = "User"
        case assistant = "Assistant"
        case system = "System"
    }

    let id: String
    var role: Role
    var content: String
    var date: Date
    var isStreaming: Bool
    var thinking: String?
}

struct ActivityItem: Identifiable, Equatable {
    enum Kind: String {
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

struct PermissionRequest: Identifiable, Equatable {
    let id: String
    var sessionID: String
    var sessionTitle: String
    var action: String
    var target: String
    var reason: String
}

struct ChangedFile: Identifiable, Equatable {
    var id: String { path }
    var path: String
    var status: String
}

struct ModelProvider: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var models: [String]
    var selectedModel: String
    var authStatus: String
}

enum PermissionDecision: String {
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

enum JSONValue: Decodable, Equatable {
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
