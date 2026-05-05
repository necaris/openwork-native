import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var currentWorkspace: Workspace?
    @Published var recentWorkspaces: [Workspace] = []
    @Published var runtimeStatus: RuntimeStatus = .stopped
    @Published var runtimeDetail = "No workspace selected"
    @Published var sessions: [OpenCodeSession] = []
    @Published var selectedSessionID: OpenCodeSession.ID?
    @Published var activity: [ActivityItem] = []
    @Published var permissionRequests: [PermissionRequest] = []
    @Published var changedFiles: [ChangedFile] = []
    @Published var providers: [ModelProvider] = [
        ModelProvider(
            name: "OpenCode",
            models: ["Configure OpenCode to load models"],
            selectedModel: "Configure OpenCode to load models",
            authStatus: "Not checked"
        )
    ]

    private let workspaceStore = WorkspaceStore()
    private let processManager = OpenCodeProcessManager()
    private let client = OpenCodeClient()

    var selectedSession: OpenCodeSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    init() {
        recentWorkspaces = workspaceStore.loadRecentWorkspaces()
    }

    func pickWorkspace() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Open Workspace"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWorkspace(at: url)
    }

    func openWorkspace(at url: URL) {
        let workspace = Workspace(path: url.path)
        currentWorkspace = workspace
        runtimeDetail = workspace.path
        recentWorkspaces.removeAll { $0.path == workspace.path }
        recentWorkspaces.insert(workspace, at: 0)
        recentWorkspaces = Array(recentWorkspaces.prefix(8))
        workspaceStore.saveRecentWorkspaces(recentWorkspaces)

        sessions = client.loadSessions(for: workspace)
        selectedSessionID = sessions.first?.id
        changedFiles = client.loadChangedFiles(for: workspace)
        activity = [
            ActivityItem(
                id: UUID(),
                kind: .runtime,
                title: "Workspace opened",
                detail: workspace.path,
                state: "Ready"
            )
        ]
    }

    func startRuntime() {
        guard let currentWorkspace else {
            runtimeStatus = .failed
            runtimeDetail = "Choose a workspace before starting OpenCode."
            return
        }

        runtimeStatus = .starting
        do {
            try processManager.start(for: currentWorkspace)
            runtimeStatus = .running
            runtimeDetail = "OpenCode running for \(currentWorkspace.displayName)"
            appendActivity(kind: .runtime, title: "OpenCode started", detail: currentWorkspace.path, state: "Running")
        } catch {
            runtimeStatus = .failed
            runtimeDetail = error.localizedDescription
            appendActivity(kind: .runtime, title: "OpenCode failed to start", detail: error.localizedDescription, state: "Failed")
        }
    }

    func stopRuntime() {
        processManager.stop()
        runtimeStatus = .stopped
        runtimeDetail = currentWorkspace?.path ?? "No workspace selected"
        appendActivity(kind: .runtime, title: "OpenCode stopped", detail: runtimeDetail, state: "Stopped")
    }

    func createSession() {
        guard currentWorkspace != nil else { return }
        let session = OpenCodeSession(
            id: UUID(),
            title: "New Session",
            createdAt: Date(),
            isRunning: false,
            messages: [
                TranscriptMessage(
                    id: UUID(),
                    role: .system,
                    content: "Session ready. Prompts will be sent to the local OpenCode server once API integration is connected.",
                    date: Date(),
                    isStreaming: false
                )
            ]
        )
        sessions.insert(session, at: 0)
        selectedSessionID = session.id
    }

    func sendPrompt(_ prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, let index = selectedSessionIndex else { return }

        sessions[index].isRunning = true
        sessions[index].messages.append(
            TranscriptMessage(id: UUID(), role: .user, content: trimmedPrompt, date: Date(), isStreaming: false)
        )
        sessions[index].messages.append(
            TranscriptMessage(
                id: UUID(),
                role: .assistant,
                content: "OpenCode streaming response placeholder. Wire OpenCodeClient.sendPrompt to the local server SSE endpoint next.",
                date: Date(),
                isStreaming: true
            )
        )
        appendActivity(kind: .step, title: "Prompt sent", detail: trimmedPrompt, state: "Running")
    }

    func stopSelectedSession() {
        guard let index = selectedSessionIndex else { return }
        sessions[index].isRunning = false
        for messageIndex in sessions[index].messages.indices {
            sessions[index].messages[messageIndex].isStreaming = false
        }
        appendActivity(kind: .step, title: "Session stopped", detail: sessions[index].title, state: "Stopped")
    }

    func resolvePermission(_ request: PermissionRequest, decision: String) {
        permissionRequests.removeAll { $0.id == request.id }
        appendActivity(kind: .tool, title: "Permission \(decision)", detail: request.action, state: decision)
    }

    func revealInFinder(_ file: ChangedFile) {
        guard let workspacePath = currentWorkspace?.path else { return }
        let url = URL(fileURLWithPath: workspacePath).appendingPathComponent(file.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openInExternalEditor(_ file: ChangedFile) {
        guard let workspacePath = currentWorkspace?.path else { return }
        let url = URL(fileURLWithPath: workspacePath).appendingPathComponent(file.path)
        NSWorkspace.shared.open(url)
    }

    private var selectedSessionIndex: Int? {
        guard let selectedSessionID else { return nil }
        return sessions.firstIndex { $0.id == selectedSessionID }
    }

    private func appendActivity(kind: ActivityItem.Kind, title: String, detail: String, state: String) {
        activity.insert(
            ActivityItem(id: UUID(), kind: kind, title: title, detail: detail, state: state),
            at: 0
        )
    }
}
