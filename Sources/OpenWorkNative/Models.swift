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
    let id: UUID
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

    let id: UUID
    var role: Role
    var content: String
    var date: Date
    var isStreaming: Bool
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
    let id: UUID
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
