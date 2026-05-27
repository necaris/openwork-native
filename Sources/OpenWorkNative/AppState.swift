import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var currentWorkspace: Workspace?
    @Published var recentWorkspaces: [Workspace] = []
    @Published var runtimeStatus: RuntimeStatus = .stopped
    @Published var runtimeDetail = "No workspace selected"
    @Published var errorBanner: String?
    @Published var sessions: [OpenCodeSession] = []
    @Published var selectedSessionID: OpenCodeSession.ID? {
        didSet {
            guard oldValue != selectedSessionID else { return }
            loadSelectedSessionMessages()
        }
    }
    @Published var activity: [ActivityItem] = []
    @Published var permissionRequests: [PermissionRequest] = []
    @Published var changedFiles: [ChangedFile] = []
    @Published var providers: [ModelProvider] = [
        ModelProvider(
            name: "OpenCode",
            models: ["Start OpenCode to load models"],
            selectedModel: "Start OpenCode to load models",
            authStatus: "Not checked"
        )
    ]

    private let workspaceStore = WorkspaceStore()
    private let processManager = OpenCodeProcessManager()
    private let gitStatusService = GitStatusService()
    private var client: OpenCodeClient?
    private var eventTask: Task<Void, Never>?
    private var sessionMessageTask: Task<Void, Never>?
    private var messagePartText: [String: String] = [:]

    var selectedSession: OpenCodeSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    init() {
        recentWorkspaces = workspaceStore.loadRecentWorkspaces()
        AppLog.app.log("AppState init — recentWorkspaces=\(self.recentWorkspaces.count, privacy: .public)")
        checkOpenCodeAvailability()
    }

    private func checkOpenCodeAvailability() {
        if let url = OpenCodeProcessManager.locateOpenCode() {
            appendActivity(kind: .runtime, title: "OpenCode found", detail: url.path, state: "Ready")
        } else {
            let message = OpenCodeProcessError.missingExecutable.localizedDescription
            errorBanner = message
            runtimeStatus = .failed
            runtimeDetail = message
            appendActivity(kind: .runtime, title: "OpenCode not found", detail: message, state: "Failed")
        }
    }

    deinit {
        eventTask?.cancel()
        sessionMessageTask?.cancel()
        processManager.stop()
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
        AppLog.state.log("openWorkspace path=\(url.path, privacy: .public)")
        stopRuntime()
        let workspace = Workspace(path: url.path)
        currentWorkspace = workspace
        runtimeDetail = workspace.path
        errorBanner = nil
        recentWorkspaces.removeAll { $0.path == workspace.path }
        recentWorkspaces.insert(workspace, at: 0)
        recentWorkspaces = Array(recentWorkspaces.prefix(8))
        workspaceStore.saveRecentWorkspaces(recentWorkspaces)

        sessions = []
        selectedSessionID = nil
        changedFiles = []
        activity = [
            ActivityItem(
                id: UUID(),
                kind: .runtime,
                title: "Workspace opened",
                detail: workspace.path,
                state: "Ready"
            )
        ]
        Task { await loadChangedFiles() }
    }

    func startRuntime() {
        guard let currentWorkspace else {
            AppLog.state.error("startRuntime: no workspace selected")
            runtimeStatus = .failed
            runtimeDetail = "Choose a workspace before starting OpenCode."
            errorBanner = runtimeDetail
            return
        }
        AppLog.state.log("startRuntime workspace=\(currentWorkspace.path, privacy: .public)")

        runtimeStatus = .starting
        errorBanner = nil
        do {
            let runtime = try processManager.start(for: currentWorkspace) { [weak self] output in
                Task { @MainActor in
                    self?.handleUnexpectedRuntimeExit(output)
                }
            }
            let newClient = OpenCodeClient(baseURL: runtime.baseURL, directory: currentWorkspace.path)
            client = newClient
            runtimeDetail = "OpenCode starting at \(runtime.baseURL.absoluteString) for \(currentWorkspace.displayName)"
            appendActivity(kind: .runtime, title: "OpenCode started", detail: currentWorkspace.path, state: "Starting")
            Task { await waitForHealthAndRefresh(client: newClient, baseURL: runtime.baseURL, workspaceName: currentWorkspace.displayName) }
        } catch {
            runtimeStatus = .failed
            runtimeDetail = error.localizedDescription
            errorBanner = error.localizedDescription
            appendActivity(kind: .runtime, title: "OpenCode failed to start", detail: error.localizedDescription, state: "Failed")
        }
    }

    func stopRuntime() {
        AppLog.state.log("stopRuntime status=\(String(describing: self.runtimeStatus), privacy: .public)")
        eventTask?.cancel()
        eventTask = nil
        sessionMessageTask?.cancel()
        sessionMessageTask = nil
        processManager.stop()
        client = nil
        for index in sessions.indices {
            sessions[index].isRunning = false
            for messageIndex in sessions[index].messages.indices {
                sessions[index].messages[messageIndex].isStreaming = false
            }
        }
        runtimeStatus = .stopped
        runtimeDetail = currentWorkspace?.path ?? "No workspace selected"
        if currentWorkspace != nil {
            appendActivity(kind: .runtime, title: "OpenCode stopped", detail: runtimeDetail, state: "Stopped")
        }
    }

    func createSession() {
        guard client != nil else {
            AppLog.state.error("createSession: no client")
            return
        }
        AppLog.state.log("createSession requested")
        Task {
            do {
                guard let client else { return }
                let session = try await client.createSession()
                AppLog.state.log("createSession ok id=\(session.id, privacy: .public)")
                sessions.insert(session, at: 0)
                selectedSessionID = session.id
            } catch {
                presentError("Could not create session", error)
            }
        }
    }

    func sendPrompt(_ prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, let sessionID = selectedSessionID, let index = selectedSessionIndex else { return }
        AppLog.state.log("sendPrompt session=\(sessionID, privacy: .public) chars=\(trimmedPrompt.count, privacy: .public)")

        sessions[index].isRunning = true
        sessions[index].messages.append(
            TranscriptMessage(id: "local-user-\(UUID().uuidString)", role: .user, content: trimmedPrompt, date: Date(), isStreaming: false, thinking: nil)
        )
        sessions[index].messages.append(
            TranscriptMessage(id: "stream-\(UUID().uuidString)", role: .assistant, content: "", date: Date(), isStreaming: true, thinking: nil)
        )
        appendActivity(kind: .step, title: "Prompt sent", detail: trimmedPrompt, state: "Running")

        Task {
            do {
                guard let client else { return }
                try await client.sendPrompt(trimmedPrompt, sessionID: sessionID)
            } catch {
                markSession(sessionID, running: false)
                presentError("Could not send prompt", error)
            }
        }
    }

    func stopSelectedSession() {
        guard let sessionID = selectedSessionID else { return }
        Task {
            do {
                try await client?.abort(sessionID: sessionID)
            } catch {
                presentError("Could not stop session", error)
            }
            markSession(sessionID, running: false)
            appendActivity(kind: .step, title: "Session stopped", detail: selectedSession?.title ?? sessionID, state: "Stopped")
        }
    }

    func resolvePermission(_ request: PermissionRequest, decision: PermissionDecision) {
        Task {
            do {
                try await client?.replyPermission(sessionID: request.sessionID, permissionID: request.id, decision: decision)
                permissionRequests.removeAll { $0.id == request.id }
                appendActivity(kind: .tool, title: "Permission \(decision.displayName)", detail: request.action, state: decision.displayName)
            } catch {
                presentError("Could not resolve permission", error)
            }
        }
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

    private func waitForHealthAndRefresh(client: OpenCodeClient, baseURL: URL, workspaceName: String) async {
        AppLog.state.log("waitForHealthAndRefresh baseURL=\(baseURL.absoluteString, privacy: .public)")
        let deadline = Date().addingTimeInterval(10)
        var lastError: Error?
        var attempts = 0
        while Date() < deadline {
            if Task.isCancelled { return }
            attempts += 1
            do {
                try await client.health()
                guard !Task.isCancelled, self.client?.baseURL == baseURL else {
                    AppLog.state.log("health succeeded but client/baseURL changed; aborting refresh")
                    return
                }
                AppLog.state.log("OpenCode healthy after \(attempts, privacy: .public) attempt(s)")
                runtimeStatus = .running
                runtimeDetail = "OpenCode running at \(baseURL.absoluteString) for \(workspaceName)"
                appendActivity(kind: .runtime, title: "OpenCode ready", detail: baseURL.absoluteString, state: "Running")
                refreshOpenCodeData()
                startEventStream()
                return
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        AppLog.state.error("OpenCode health failed after \(attempts, privacy: .public) attempts: \(lastError?.localizedDescription ?? "timeout", privacy: .public)")
        guard self.client?.baseURL == baseURL else { return }
        let detail = lastError?.localizedDescription ?? "Health check timed out."
        runtimeStatus = .failed
        runtimeDetail = detail
        errorBanner = "OpenCode did not become ready: \(detail)"
        appendActivity(kind: .runtime, title: "OpenCode failed to become ready", detail: detail, state: "Failed")
    }

    private func refreshOpenCodeData() {
        Task {
            await loadSessions()
            await loadChangedFiles()
            await loadProviders()
        }
    }

    private func loadSessions() async {
        do {
            guard let client else { return }
            sessions = try await client.loadSessions()
            AppLog.state.log("Loaded \(self.sessions.count, privacy: .public) sessions")
            selectedSessionID = sessions.first?.id
        } catch {
            presentError("Could not load sessions", error)
        }
    }

    private func loadSelectedSessionMessages() {
        sessionMessageTask?.cancel()
        guard let sessionID = selectedSessionID else { return }
        sessionMessageTask = Task {
            do {
                guard let client else { return }
                let messages = try await client.loadMessages(sessionID: sessionID)
                guard !Task.isCancelled, let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
                sessions[index].messages = messages
            } catch {
                presentError("Could not load message history", error)
            }
        }
    }

    private func loadChangedFiles() async {
        guard let currentWorkspace else { return }
        do {
            if let files = try await client?.loadChangedFiles() {
                changedFiles = files
            } else {
                changedFiles = await gitStatusService.changedFiles(in: currentWorkspace)
            }
        } catch {
            changedFiles = await gitStatusService.changedFiles(in: currentWorkspace)
        }
    }

    private func loadProviders() async {
        do {
            if let loadedProviders = try await client?.loadProviders(), !loadedProviders.isEmpty {
                providers = loadedProviders
                AppLog.state.log("Loaded \(loadedProviders.count, privacy: .public) provider(s)")
            }
        } catch {
            let message = error.localizedDescription
            errorBanner = "OpenCode model/provider configuration needs attention."
            providers = [ModelProvider(name: "OpenCode", models: ["Unavailable"], selectedModel: "Unavailable", authStatus: message)]
        }
    }

    private func startEventStream() {
        eventTask?.cancel()
        guard let client else { return }
        let request = client.makeEventRequest()
        AppLog.events.log("Opening SSE stream: \(request.url?.absoluteString ?? "<nil>", privacy: .public)")
        eventTask = Task {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    AppLog.events.error("SSE stream non-200: \(http.statusCode, privacy: .public)")
                    throw OpenCodeClientError.serverError(http.statusCode, "Event stream failed")
                }
                AppLog.events.log("SSE stream open")

                var pendingLines: [String] = []
                for try await line in bytes.lines {
                    guard !Task.isCancelled else { break }
                    if line.isEmpty {
                        await consumeSSELines(&pendingLines)
                    } else {
                        pendingLines.append(line)
                    }
                }
                AppLog.events.log("SSE stream ended (loop exit)")
            } catch is CancellationError {
                AppLog.events.log("SSE stream cancelled")
                return
            } catch {
                AppLog.events.error("SSE stream failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self.presentError("OpenCode event stream ended", error)
                }
            }
        }
    }

    private func consumeSSELines(_ lines: inout [String]) async {
        let events = SSEParser.events(from: lines + [""])
        lines.removeAll()
        for eventText in events {
            guard let data = eventText.data(using: .utf8), let event = try? JSONDecoder().decode(OpenCodeEvent.self, from: data) else { continue }
            await MainActor.run {
                self.apply(event)
            }
        }
    }

    private func apply(_ event: OpenCodeEvent) {
        AppLog.events.debug("event type=\(event.type, privacy: .public) session=\(event.sessionID ?? "-", privacy: .public) message=\(event.messageID ?? "-", privacy: .public)")
        switch event.type {
        case "message.updated":
            applyMessageUpdated(event)
        case "message.part.updated":
            applyMessagePartUpdated(event)
        case "message.part.delta":
            applyMessagePartDelta(event)
        case "session.status", "session.idle":
            if let sessionID = event.sessionID {
                markSession(sessionID, running: event.sessionStatus == "busy" && event.type != "session.idle")
            }
        case "session.error":
            appendActivity(kind: .step, title: "Session error", detail: event.properties["error"]?.displayValue ?? "Unknown error", state: "Failed")
            if let sessionID = event.sessionID { markSession(sessionID, running: false) }
        case "permission.asked":
            if let request = event.permissionRequest {
                upsertPermission(request)
            }
        case "permission.replied":
            if let requestID = event.properties["requestID"]?.stringValue {
                removePermission(id: requestID)
            }
        case "todo.updated":
            if let todos = event.todos {
                activity.insert(contentsOf: todos, at: 0)
            }
        case "file.edited", "file.watcher.updated", "session.diff":
            Task { await loadChangedFiles() }
        default:
            break
        }
    }

    private func applyMessageUpdated(_ event: OpenCodeEvent) {
        guard let info = event.properties["info"]?.objectValue,
              let messageID = info["id"]?.stringValue,
              let sessionID = info["sessionID"]?.stringValue,
              let role = info["role"]?.stringValue else { return }
        let appRole: TranscriptMessage.Role = role == "assistant" ? .assistant : .user
        upsertMessage(sessionID: sessionID, messageID: messageID, role: appRole, content: nil, thinking: nil, streaming: role == "assistant")
    }

    private func applyMessagePartDelta(_ event: OpenCodeEvent) {
        guard let sessionID = event.properties["sessionID"]?.stringValue,
              let messageID = event.properties["messageID"]?.stringValue,
              let partID = event.properties["partID"]?.stringValue,
              let delta = event.properties["delta"]?.stringValue else { return }
        let field = event.properties["field"]?.stringValue ?? "text"
        let current = messagePartText[partID] ?? ""
        let newText = current + delta
        messagePartText[partID] = newText

        if field == "reasoning" {
            upsertMessage(sessionID: sessionID, messageID: messageID, role: .assistant, content: nil, thinking: newText, streaming: true)
        } else {
            upsertMessage(sessionID: sessionID, messageID: messageID, role: .assistant, content: newText, thinking: nil, streaming: true)
        }
    }

    private func applyMessagePartUpdated(_ event: OpenCodeEvent) {
        guard let sessionID = event.sessionID, let messageID = event.messageID else { return }
        let partType = event.partType ?? "text"
        let partID = event.partID ?? UUID().uuidString
        let newText: String
        if let delta = event.textDelta {
            let current = messagePartText[partID] ?? ""
            newText = current + delta
        } else {
            newText = event.partText ?? ""
        }
        messagePartText[partID] = newText

        if partType == "reasoning" {
            upsertMessage(sessionID: sessionID, messageID: messageID, role: .assistant, content: nil, thinking: newText, streaming: true)
        } else if partType == "text" {
            upsertMessage(sessionID: sessionID, messageID: messageID, role: .assistant, content: newText, thinking: nil, streaming: true)
        } else if partType == "tool" {
            let tool = event.properties["part"]?.objectValue?["tool"]?.stringValue ?? "Tool"
            let state = event.properties["part"]?.objectValue?["state"]?.objectValue?["status"]?.stringValue ?? "running"
            appendActivity(kind: .tool, title: tool, detail: messageID, state: state)
        }
    }

    private func upsertMessage(sessionID: String, messageID: String, role: TranscriptMessage.Role, content: String?, thinking: String?, streaming: Bool) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        if let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }) {
            if let content { sessions[sessionIndex].messages[messageIndex].content = content }
            if let thinking { sessions[sessionIndex].messages[messageIndex].thinking = thinking }
            sessions[sessionIndex].messages[messageIndex].isStreaming = streaming
        } else if let placeholderIndex = sessions[sessionIndex].messages.lastIndex(where: { $0.id.hasPrefix("stream-") && $0.isStreaming }) {
            sessions[sessionIndex].messages[placeholderIndex] = TranscriptMessage(
                id: messageID,
                role: role,
                content: content ?? "",
                date: Date(),
                isStreaming: streaming,
                thinking: thinking
            )
        } else {
            sessions[sessionIndex].messages.append(
                TranscriptMessage(id: messageID, role: role, content: content ?? "", date: Date(), isStreaming: streaming, thinking: thinking)
            )
        }
    }

    private func removePermission(id: String) {
        permissionRequests.removeAll { $0.id == id }
    }

    private func upsertPermission(_ request: PermissionRequest) {
        var request = request
        request.sessionTitle = sessions.first(where: { $0.id == request.sessionID })?.title ?? request.sessionID
        if let index = permissionRequests.firstIndex(where: { $0.id == request.id }) {
            permissionRequests[index] = request
        } else {
            permissionRequests.insert(request, at: 0)
        }
    }

    private func markSession(_ sessionID: String, running: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].isRunning = running
        if !running {
            for messageIndex in sessions[index].messages.indices {
                sessions[index].messages[messageIndex].isStreaming = false
            }
        }
    }

    private func handleUnexpectedRuntimeExit(_ output: String) {
        eventTask?.cancel()
        client = nil
        runtimeStatus = .failed
        runtimeDetail = output
        errorBanner = output
        for index in sessions.indices {
            sessions[index].isRunning = false
        }
        appendActivity(kind: .runtime, title: "OpenCode exited unexpectedly", detail: output, state: "Failed")
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

    private func presentError(_ title: String, _ error: Error) {
        let message = "\(title): \(error.localizedDescription)"
        errorBanner = message
        appendActivity(kind: .runtime, title: title, detail: error.localizedDescription, state: "Failed")
    }
}
