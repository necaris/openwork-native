import Foundation

struct OpenCodeClient {
    func loadSessions(for workspace: Workspace) -> [OpenCodeSession] {
        [
            OpenCodeSession(
                id: UUID(),
                title: "Workspace Session",
                createdAt: Date(),
                isRunning: false,
                messages: [
                    TranscriptMessage(
                        id: UUID(),
                        role: .system,
                        content: "OpenCode API integration is scaffolded. Connect session listing, message history, and SSE streaming here.",
                        date: Date(),
                        isStreaming: false
                    )
                ]
            )
        ]
    }

    func loadChangedFiles(for workspace: Workspace) -> [ChangedFile] {
        []
    }
}
