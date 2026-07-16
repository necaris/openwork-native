import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var currentWorkspace: Workspace?
    @Published var recentWorkspaces: [Workspace] = []
    @Published var runtimeStatus: RuntimeStatus = .stopped
    @Published var runtimeDetail = "No workspace selected"
    @Published var errorBanner: String?
    @Published var openCodeAvailable: Bool = false
    @Published var sessions: [OpenCodeSession] = []
    @Published var selectedSessionID: OpenCodeSession.ID? {
        didSet {
            guard oldValue != selectedSessionID else { return }
            saveSelectedSession()
            loadSelectedSessionMessages()
        }
    }
    @Published var activity: [ActivityItem] = []
    @Published var expandedMessageIDs: Set<String> = []
    @Published var scrollToMessageID: String?
    @Published var permissionRequests: [PermissionRequest] = []
    @Published var changedFiles: [ChangedFile] = []
    @Published var inventory: [WorkspaceInventoryItem] = []
    @Published var showingManagementSheet = false
    @Published var isInventoryInspectorVisible = false
    @Published var selectedDefaultModelID: String?
    @Published var sessionModelOverrides: [OpenCodeSession.ID: SessionModel] = [:]
    @Published var isUpdatingDefaultModel = false
    @Published var showAllModels = false
    @Published var providers: [ModelProvider] = [
        ModelProvider(
            id: "opencode",
            name: "OpenCode",
            models: ["Start OpenCode to load models"],
            selectedModel: "Start OpenCode to load models",
            authStatus: "Not checked"
        )
    ]

    private let workspaceStore: WorkspaceStore
    private let processManager = OpenCodeProcessManager()
    private let gitStatusService = GitStatusService()
    private let inventoryService = WorkspaceInventoryService()
    private let activityLimit = 100
    var client: OpenCodeClient?
    private var eventTask: Task<Void, Never>?
    private var sessionMessageTask: Task<Void, Never>?
    private var restoredSessionID: String?

    var selectedSession: OpenCodeSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    var availableDefaultModelIDs: [String] {
        let connected = providers.filter { $0.authStatus == "Connected" }.flatMap(\.modelIDs)
        let source = connected.isEmpty ? providers.flatMap(\.modelIDs) : connected
        return source.sorted()
    }

    /// Available models grouped by provider, so long lists can render as per-provider sections/submenus.
    /// When `showAllModels` is off, applies `ModelFiltering`'s default filters and generation trimming.
    var groupedAvailableModels: [(provider: ModelProvider, modelIDs: [String])] {
        let connected = providers.filter { $0.authStatus == "Connected" }
        let source = connected.isEmpty ? providers : connected
        return source
            .filter { showAllModels || !ModelFiltering.isProviderHidden($0) }
            .map { provider in
                let names = showAllModels
                    ? provider.models.filter { $0 != "No configured model" }
                    : ModelFiltering.slimmedModelNames(for: provider)
                let modelIDs = names.map { "\(provider.id)/\($0)" }.sorted()
                return (provider, modelIDs)
            }
            .filter { !$0.1.isEmpty }
            .sorted { $0.0.name < $1.0.name }
    }

    func displayModel(for session: OpenCodeSession) -> SessionModel? {
        sessionModelOverrides[session.id] ?? session.model
    }

    /// Strips the "provider/" prefix from a model ID for display inside an already-grouped section.
    func modelDisplayName(_ modelID: String) -> String {
        guard let separator = modelID.firstIndex(of: "/") else { return modelID }
        return String(modelID[modelID.index(after: separator)...])
    }

    var openCodeConfigURL: URL? {
        guard let currentWorkspace else { return nil }
        let root = URL(fileURLWithPath: currentWorkspace.path, isDirectory: true)
        let candidates = [
            root.appendingPathComponent("config.json"),
            root.appendingPathComponent("config.jsonc"),
            root.appendingPathComponent("opencode.json"),
            root.appendingPathComponent("opencode.jsonc"),
            root.appendingPathComponent(".opencode/config.json"),
            root.appendingPathComponent(".opencode/config.jsonc"),
            root.appendingPathComponent(".opencode/opencode.json"),
            root.appendingPathComponent(".opencode/opencode.jsonc")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
            ?? root.appendingPathComponent("opencode.jsonc")
    }

    init(workspaceStore: WorkspaceStore = WorkspaceStore()) {
        self.workspaceStore = workspaceStore
        recentWorkspaces = workspaceStore.loadRecentWorkspaces()
        AppLog.app.log("AppState init — recentWorkspaces=\(self.recentWorkspaces.count, privacy: .public)")
        restoreLastWorkspace()
        checkOpenCodeAvailability()
    }

    private func restoreLastWorkspace() {
        guard let workspace = recentWorkspaces.first else { return }
        currentWorkspace = workspace
        restoredSessionID = workspaceStore.loadLastSessionID(for: workspace)
        runtimeDetail = workspace.path
        activity = [
            ActivityItem(
                id: UUID(),
                kind: .runtime,
                title: "Workspace restored",
                detail: workspace.path,
                state: "Ready"
            )
        ]
        Task { await loadChangedFiles() }
        Task { await loadInventory() }
        Task {
            // Delay auto-start slightly to allow UI to render first
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                self.startRuntime()
            }
        }
    }

    private func checkOpenCodeAvailability() {
        if OpenCodeProcessManager.locateOpenCode() != nil {
            openCodeAvailable = true
        } else {
            openCodeAvailable = false
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

    func openWorkspace(at url: URL, autoStart: Bool = true) {
        AppLog.state.log("openWorkspace path=\(url.path, privacy: .public)")
        stopRuntime()
        let workspace = Workspace(path: url.path)
        currentWorkspace = workspace
        restoredSessionID = workspaceStore.loadLastSessionID(for: workspace)
        runtimeDetail = workspace.path
        errorBanner = nil
        recentWorkspaces.removeAll { $0.path == workspace.path }
        recentWorkspaces.insert(workspace, at: 0)
        recentWorkspaces = Array(recentWorkspaces.prefix(8))
        workspaceStore.saveRecentWorkspaces(recentWorkspaces)

        sessions = []
        selectedSessionID = nil
        changedFiles = []
        inventory = []
        selectedDefaultModelID = nil
        sessionModelOverrides = [:]
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
        Task { await loadInventory() }
        
        if autoStart {
            startRuntime()
        }
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
        guard let client else {
            AppLog.state.error("createSession: no client")
            return
        }
        let title = currentWorkspace?.displayName ?? "New Session"
        AppLog.state.log("createSession requested title=\(title, privacy: .public)")
        Task {
            do {
                let session = try await client.createSession(title: title)
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
        let modelOverride = sessionModelOverrides[sessionID]
        AppLog.state.log("sendPrompt session=\(sessionID, privacy: .public) chars=\(trimmedPrompt.count, privacy: .public)")

        sessions[index].isRunning = true
        sessions[index].messages.append(
            TranscriptMessage(id: "local-user-\(UUID().uuidString)", role: .user, parts: [TranscriptMessagePart(id: "local-part", type: "text", text: trimmedPrompt)], date: Date(), isStreaming: false)
        )
        sessions[index].messages.append(
            TranscriptMessage(id: "stream-\(UUID().uuidString)", role: .assistant, parts: [], date: Date(), isStreaming: true, model: modelOverride)
        )
        sessions[index].isRunning = true
        appendActivity(kind: .step, title: "Prompt sent", detail: trimmedPrompt, state: "Running", sessionID: sessionID)

        Task {
            do {
                guard let client else { return }
                try await client.sendPrompt(trimmedPrompt, sessionID: sessionID, model: modelOverride)
            } catch {
                markSession(sessionID, running: false)
                presentError("Could not send prompt", error)
            }
        }
    }

    // Re-run the user prompt that produced the given assistant turn. Reverts to that
    // user message (restoring files) and resends its original text unchanged.
    func retryAssistantMessage(_ messageID: String) {
        guard let index = selectedSessionIndex else { return }
        let messages = sessions[index].messages
        guard let assistantPos = messages.firstIndex(where: { $0.id == messageID }),
              let userPos = messages[..<assistantPos].lastIndex(where: { $0.role == .user }) else { return }
        let userMessage = messages[userPos]
        resend(userMessage.content, fromMessageID: userMessage.id)
    }

    // Resend a previously sent user prompt with edited text. Reverts to that user
    // message (restoring files) and sends the new text in its place.
    func editAndResend(_ messageID: String, newText: String) {
        resend(newText, fromMessageID: messageID)
    }

    // A message can be retried/edited once it has a server-assigned ID and the session
    // is idle — local stubs and in-flight turns are not eligible.
    func canRevert(to message: TranscriptMessage) -> Bool {
        guard let session = selectedSession, !session.isRunning, !message.isStreaming else { return false }
        return message.id.hasPrefix("msg")
    }

    private func resend(_ prompt: String, fromMessageID messageID: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let sessionID = selectedSessionID, let index = selectedSessionIndex else { return }
        guard let position = sessions[index].messages.firstIndex(where: { $0.id == messageID }) else { return }
        AppLog.state.log("resend session=\(sessionID, privacy: .public) from=\(messageID, privacy: .public)")

        // Drop the reverted turn and everything after it locally; the server drops the
        // same messages when the resent prompt commits the revert.
        sessions[index].messages.removeSubrange(position...)

        Task {
            do {
                guard let client else { return }
                try await client.revert(sessionID: sessionID, messageID: messageID)
            } catch {
                presentError("Could not revert before resending", error)
                loadSelectedSessionMessages()
                return
            }
            sendPrompt(trimmed)
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
            appendActivity(kind: .step, title: "Session stopped", detail: selectedSession?.title ?? sessionID, state: "Stopped", sessionID: sessionID)
        }
    }

    func resolvePermission(_ request: PermissionRequest, decision: PermissionDecision) {
        Task {
            do {
                try await client?.replyPermission(sessionID: request.sessionID, permissionID: request.id, decision: decision)
                permissionRequests.removeAll { $0.id == request.id }
                appendActivity(kind: .tool, title: "Permission \(decision.displayName)", detail: request.action, state: decision.displayName, sessionID: request.sessionID)
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

    func revealInventoryItem(_ item: WorkspaceInventoryItem) {
        let url: URL
        if item.path.hasPrefix("/") {
            url = URL(fileURLWithPath: item.path)
        } else {
            guard let workspacePath = currentWorkspace?.path else { return }
            url = URL(fileURLWithPath: workspacePath).appendingPathComponent(item.path)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealOpenCodeConfig() {
        guard let configURL = openCodeConfigURL else {
            errorBanner = "Choose a workspace before opening OpenCode configuration."
            return
        }

        if FileManager.default.fileExists(atPath: configURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([configURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([configURL.deletingLastPathComponent()])
            errorBanner = "No OpenCode config found in this workspace. Create or edit config.json outside OpenWork, then restart OpenCode."
        }
    }

    func selectDefaultModel(_ modelID: String) {
        guard !modelID.isEmpty, selectedDefaultModelID != modelID else { return }
        guard let client else {
            errorBanner = "Start OpenCode before changing the default model."
            return
        }

        let previousModelID = selectedDefaultModelID
        selectedDefaultModelID = modelID
        isUpdatingDefaultModel = true
        Task {
            do {
                selectedDefaultModelID = try await client.updateDefaultModel(modelID)
                appendActivity(kind: .runtime, title: "Default model changed", detail: modelID, state: "Updated")
                await loadProviders()
            } catch {
                selectedDefaultModelID = previousModelID
                presentError("Could not update default model", error)
            }
            isUpdatingDefaultModel = false
        }
    }

    func selectSessionModel(_ modelID: String, for session: OpenCodeSession) {
        guard let model = sessionModel(from: modelID) else { return }
        sessionModelOverrides[session.id] = model
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index].model = model
        }
        appendActivity(kind: .runtime, title: "Session model changed", detail: modelID, state: "Updated", sessionID: session.id)
    }

    private func sessionModel(from modelID: String) -> SessionModel? {
        guard let separator = modelID.firstIndex(of: "/") else { return nil }
        let providerID = String(modelID[..<separator])
        let modelID = String(modelID[modelID.index(after: separator)...])
        guard !providerID.isEmpty, !modelID.isEmpty else { return nil }
        return SessionModel(modelID: modelID, providerID: providerID)
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
            await loadInventory()
        }
    }

    private func loadSessions() async {
        do {
            guard let client else { return }
            sessions = try await client.loadSessions()
            AppLog.state.log("Loaded \(self.sessions.count, privacy: .public) sessions")
            if let restoredSessionID, sessions.contains(where: { $0.id == restoredSessionID }) {
                selectedSessionID = restoredSessionID
            } else {
                selectedSessionID = sessions.first?.id
            }
            restoredSessionID = nil
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

    private func loadInventory() async {
        guard let currentWorkspace else {
            inventory = []
            return
        }
        // Prefer the server's resolved inventory (deduped, with live MCP status);
        // fall back to scanning the workspace before the runtime is up.
        if let client, let items = try? await client.loadInventory() {
            inventory = items
            return
        }
        inventory = await inventoryService.loadInventory(in: currentWorkspace)
    }

    private func loadProviders() async {
        do {
            guard let client else { return }
            async let loadedProviders = client.loadProviders()
            async let config = client.loadConfig()
            let (providersResult, configResult) = try await (loadedProviders, config)
            if !providersResult.isEmpty {
                providers = providersResult
                AppLog.state.log("Loaded \(providersResult.count, privacy: .public) provider(s)")
            }
            selectedDefaultModelID = configResult.model
        } catch {
            let message = error.localizedDescription
            errorBanner = "OpenCode model/provider configuration needs attention. Edit OpenCode config outside OpenWork, then restart OpenCode."
            providers = [ModelProvider(id: "opencode", name: "OpenCode", models: ["Unavailable"], selectedModel: "Unavailable", authStatus: message)]
        }
    }

    private func startEventStream() {
        eventTask?.cancel()
        guard let client else { return }
        let request = client.makeEventRequest()
        AppLog.events.log("Opening SSE stream: \(request.url?.absoluteString ?? "<nil>", privacy: .public)")
        eventTask = Task {
            while !Task.isCancelled {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        AppLog.events.error("SSE stream non-200: \(http.statusCode, privacy: .public)")
                        throw OpenCodeClientError.serverError(http.statusCode, "Event stream failed")
                    }
                    AppLog.events.log("SSE stream open")

                    var pendingLines: [String] = []
                    var lineBuffer: [UInt8] = []
                    for try await byte in bytes {
                        guard !Task.isCancelled else { break }
                        if byte == 10 { // \n
                            if let line = String(bytes: lineBuffer, encoding: .utf8) {
                                let trimmed = line.hasSuffix("\r") ? String(line.dropLast()) : line
                                if trimmed.isEmpty {
                                    await consumeSSELines(&pendingLines)
                                } else {
                                    pendingLines.append(trimmed)
                                }
                            }
                            lineBuffer.removeAll(keepingCapacity: true)
                        } else {
                            lineBuffer.append(byte)
                        }
                    }
                    AppLog.events.log("SSE stream ended (loop exit), reconnecting...")
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second backoff
                } catch is CancellationError {
                    AppLog.events.log("SSE stream cancelled")
                    return
                } catch {
                    AppLog.events.error("SSE stream failed: \(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        self.presentError("OpenCode event stream ended", error)
                    }
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 second backoff on error
                }
            }
        }
    }

    private func consumeSSELines(_ lines: inout [String]) async {
        let events = SSEParser.events(from: lines + [""])
        lines.removeAll()
        for eventText in events {
            guard let data = eventText.data(using: .utf8) else { continue }
            do {
                let event = try JSONDecoder().decode(OpenCodeEvent.self, from: data)
                await MainActor.run {
                    self.appendRawEventLog(eventText)
                    self.apply(event)
                }
            } catch {
                AppLog.events.error("Failed to decode SSE event: \(error.localizedDescription, privacy: .public)\n\(eventText, privacy: .public)")
            }
        }
    }

    func apply(_ event: OpenCodeEvent) {
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
                if event.sessionStatus == "retry" {
                    // Provider throttling (e.g. OpenAI usage-limit errors) surfaces here, not as
                    // session.error or message.updated's info.error — the server is retrying on
                    // its own, so this is a transient status note, not a terminal message error.
                    let statusObject = event.properties["status"]?.objectValue
                    let message = statusObject?["message"]?.stringValue ?? "Retrying…"
                    let attempt = statusObject?["attempt"]?.intValue
                    let detail = attempt.map { "\(message) (attempt \($0))" } ?? message
                    setSessionStatusNote(detail, for: sessionID)
                    markSession(sessionID, running: true)
                    appendActivity(kind: .step, title: "Retrying", detail: detail, state: "Retry", sessionID: sessionID)
                } else {
                    setSessionStatusNote(nil, for: sessionID)
                    markSession(sessionID, running: event.sessionStatus == "busy" && event.type != "session.idle")
                }
            }
        case "session.updated":
            applySessionUpdated(event)
        case "session.next.model.switched":
            applyModelSwitched(event)
        case "session.next.agent.switched":
            if let agent = event.properties["agent"]?.stringValue {
                appendActivity(kind: .runtime, title: "Agent switched", detail: agent, state: agent, sessionID: event.sessionID)
            }
        case "session.error":
            let detail = event.sessionErrorMessage
            let sessionID = event.sessionID ?? selectedSessionID
            if let sessionID {
                attachSessionError(detail, to: sessionID)
                markSession(sessionID, running: false)
            }
            appendActivity(kind: .step, title: "Session error", detail: detail, state: "Failed", sessionID: sessionID)
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
                activity.insert(contentsOf: todos.map { todo in
                    var todo = todo
                    todo.sessionID = event.sessionID
                    return todo
                }, at: 0)
                trimActivity()
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
        let isCompleted = info["time"]?.objectValue?["completed"] != nil || info["finish"] != nil
        let isStreaming = role == "assistant" && !isCompleted

        // Some provider failures (e.g. OpenAI usage-limit errors) surface only through
        // message.updated's info.error rather than a top-level session.error event, and can
        // omit time.completed/finish entirely — without this, the bubble spins forever with
        // no visible error, unlike the clear error banner Anthropic failures already get.
        if let detail = OpenCodeEvent.messageInfoErrorMessage(from: info) {
            attachSessionError(detail, to: sessionID)
            markSession(sessionID, running: false)
            appendActivity(kind: .step, title: "Session error", detail: detail, state: "Failed", sessionID: sessionID)
            if let session = sessions.first(where: { $0.id == sessionID }) {
                writeDebugLog(for: session)
            }
            return
        }

        upsertMessage(sessionID: sessionID, messageID: messageID, role: appRole, part: nil, streaming: isStreaming)
    }

    private func applyMessagePartDelta(_ event: OpenCodeEvent) {
        guard let sessionID = event.properties["sessionID"]?.stringValue,
              let messageID = event.properties["messageID"]?.stringValue,
              let partID = event.properties["partID"]?.stringValue,
              let delta = event.properties["delta"]?.stringValue else { return }
        let field = event.properties["field"]?.stringValue ?? "text"
        
        // message.part.delta provides an incremental piece. We look up the existing message part if any.
        // It's applied in upsertMessage by finding the matching part and appending.
        let role = roleForMessage(sessionID: sessionID, messageID: messageID) ?? .assistant
        guard role == .assistant else { return }
        
        let streaming: Bool
        if let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
            streaming = sessions[sessionIndex].isRunning
        } else {
            streaming = true
        }
        
        if field == "reasoning" {
            upsertMessage(sessionID: sessionID, messageID: messageID, role: .assistant, part: TranscriptMessagePart(id: partID, type: "reasoning", text: delta), streaming: streaming, isDelta: true)
        } else {
            upsertMessage(sessionID: sessionID, messageID: messageID, role: .assistant, part: TranscriptMessagePart(id: partID, type: "text", text: delta), streaming: streaming, isDelta: true)
        }
    }

    private func applyMessagePartUpdated(_ event: OpenCodeEvent) {
        guard let sessionID = event.sessionID, let messageID = event.messageID else { return }
        let partType = event.partType ?? "text"
        let partID = event.partID ?? UUID().uuidString
        let text = event.textDelta ?? event.partText ?? ""

        // Role must come from the existing message, not be hardcoded.
        // message.part.updated fires for user echoes too (with partType "text").
        let role = roleForMessage(sessionID: sessionID, messageID: messageID) ?? .assistant
        
        let streaming: Bool
        if let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
            streaming = sessions[sessionIndex].isRunning
        } else {
            streaming = role == .assistant
        }

        if partType == "reasoning" || partType == "text" {
            upsertMessage(sessionID: sessionID, messageID: messageID, role: role, part: TranscriptMessagePart(id: partID, type: partType, text: text), streaming: streaming, isDelta: event.textDelta != nil)
        } else if partType == "tool" {
            let partObject = event.properties["part"]?.objectValue
            let tool = partObject?["tool"]?.stringValue ?? "tool"
            let state = partObject?["state"]?.objectValue
            let status = state?["status"]?.stringValue ?? "running"
            let toolText = TranscriptMessagePart.toolCallText(
                tool: tool,
                title: state?["title"]?.stringValue,
                status: status,
                output: state?["output"]?.displayValue
            )
            upsertMessage(sessionID: sessionID, messageID: messageID, role: role, part: TranscriptMessagePart(id: partID, type: partType, text: toolText), streaming: streaming, isDelta: false)
            upsertActivity(kind: .tool, title: tool, detail: toolActionDetail(event, fallback: messageID), state: status, sessionID: sessionID, sourceID: partID, messageID: messageID)
        }
    }

    // The action a tool row describes: OpenCode's human-readable state.title when
    // present, else the tool's input/arguments, else the message ID as before.
    private func toolActionDetail(_ event: OpenCodeEvent, fallback: String) -> String {
        let part = event.properties["part"]?.objectValue
        let state = part?["state"]?.objectValue
        if let title = state?["title"]?.stringValue, !title.isEmpty {
            return title
        }
        if let input = state?["input"] {
            let rendered = input.displayValue
            if !rendered.isEmpty { return rendered }
        }
        if let arguments = part?["toolCall"]?.objectValue?["arguments"] {
            let rendered = arguments.displayValue
            if !rendered.isEmpty { return rendered }
        }
        return fallback
    }

    private func applySessionUpdated(_ event: OpenCodeEvent) {
        guard let info = event.properties["info"]?.objectValue,
              let sessionID = info["id"]?.stringValue,
              let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        if let cost = info["cost"]?.doubleValue { sessions[index].cost = cost }
        if let tokensObject = info["tokens"]?.objectValue {
            sessions[index].tokens = TokenUsage(
                input: tokensObject["input"]?.intValue ?? sessions[index].tokens.input,
                output: tokensObject["output"]?.intValue ?? sessions[index].tokens.output,
                reasoning: tokensObject["reasoning"]?.intValue ?? sessions[index].tokens.reasoning,
                cacheRead: tokensObject["cache"]?.objectValue?["read"]?.intValue ?? sessions[index].tokens.cacheRead,
                cacheWrite: tokensObject["cache"]?.objectValue?["write"]?.intValue ?? sessions[index].tokens.cacheWrite
            )
        }
        if let modelObject = info["model"]?.objectValue {
            let modelID = modelObject["id"]?.stringValue ?? modelObject["modelID"]?.stringValue
            let providerID = modelObject["providerID"]?.stringValue
            if let modelID, let providerID {
                sessions[index].model = SessionModel(modelID: modelID, providerID: providerID)
            }
        }
    }

    private func applyModelSwitched(_ event: OpenCodeEvent) {
        guard let sessionID = event.sessionID else { return }
        let modelID = event.properties["modelID"]?.stringValue
            ?? event.properties["model"]?.objectValue?["modelID"]?.stringValue
            ?? event.properties["model"]?.objectValue?["id"]?.stringValue
        let providerID = event.properties["providerID"]?.stringValue
            ?? event.properties["model"]?.objectValue?["providerID"]?.stringValue
        if let index = sessions.firstIndex(where: { $0.id == sessionID }),
           let modelID, let providerID {
            let previous = sessions[index].model?.modelID
            sessions[index].model = SessionModel(modelID: modelID, providerID: providerID)
            let detail = previous.map { "\($0) → \(modelID)" } ?? modelID
            appendActivity(kind: .runtime, title: "Model switched", detail: detail, state: modelID, sessionID: sessionID)
        }
    }

    private func upsertMessage(sessionID: String, messageID: String, role: TranscriptMessage.Role, part: TranscriptMessagePart?, streaming: Bool, isDelta: Bool = false) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        
        var session = sessions[sessionIndex]
        defer { 
            sessions[sessionIndex] = session 
            writeDebugLog(for: session)
        }

        if let messageIndex = session.messages.firstIndex(where: { $0.id == messageID }) {
            if let part {
                if let partIndex = session.messages[messageIndex].parts.firstIndex(where: { $0.id == part.id || ($0.id == "local-part" && role == .user) }) {
                    if isDelta {
                        session.messages[messageIndex].parts[partIndex].text += part.text
                    } else {
                        session.messages[messageIndex].parts[partIndex] = part
                    }
                } else {
                    session.messages[messageIndex].parts.append(part)
                }
            }
            session.messages[messageIndex].isStreaming = streaming
            return
        }

        // Reconcile local stubs with server-assigned IDs: the assistant stub is
        // a streaming placeholder, the user stub is the locally-inserted prompt.
        let stubPrefix = role == .assistant ? "stream-" : "local-user-"
        if let stubIndex = session.messages.lastIndex(where: { $0.role == role && $0.id.hasPrefix(stubPrefix) }) {
            var existing = session.messages[stubIndex]
            if let part {
                if let partIndex = existing.parts.firstIndex(where: { $0.id == part.id || ($0.id == "local-part" && role == .user) }) {
                    if isDelta {
                        existing.parts[partIndex].text += part.text
                    } else {
                        existing.parts[partIndex] = part
                    }
                } else {
                    existing.parts.append(part)
                }
            }
            session.messages[stubIndex] = TranscriptMessage(
                id: messageID,
                role: role,
                parts: existing.parts,
                date: existing.date,
                isStreaming: streaming
            )
            return
        }

        session.messages.append(
            TranscriptMessage(id: messageID, role: role, parts: part != nil ? [part!] : [], date: Date(), isStreaming: streaming)
        )
    }

    // Raw SSE event bodies, one per line, so provider-specific failure shapes (which vary
    // by provider and aren't all known in advance) can be inspected after the fact instead
    // of guessed at from AppLog's truncated type/session/message summary.
    private func appendRawEventLog(_ eventText: String) {
        guard let workspace = currentWorkspace else { return }
        let logURL = URL(fileURLWithPath: workspace.path).appendingPathComponent("opencode_events_log.jsonl")
        let compact = eventText.replacingOccurrences(of: "\n", with: "")
        let line = "[\(Date())] \(compact)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? data.write(to: logURL)
        }
    }

    private func writeDebugLog(for session: OpenCodeSession) {
        guard let workspace = currentWorkspace else { return }
        let logURL = URL(fileURLWithPath: workspace.path).appendingPathComponent("chat_debug_log.txt")
        var log = "=== [\(Date())] Session: \(session.id) ===\n"
        log += "Running: \(session.isRunning)\n\n"
        for msg in session.messages {
            log += "[\(msg.role.rawValue)] (id: \(msg.id), streaming: \(msg.isStreaming))\n"
            if let errorMessage = msg.errorMessage {
                log += "  - Error: \(errorMessage.replacingOccurrences(of: "\n", with: "\\n"))\n"
            }
            for part in msg.parts {
                log += "  - Part: \(part.type) (\(part.id))\n"
                log += "    Text: \(part.text.replacingOccurrences(of: "\n", with: "\\n"))\n"
            }
            log += "\n"
        }
        
        if let data = log.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    private func roleForMessage(sessionID: String, messageID: String) -> TranscriptMessage.Role? {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return nil }
        return sessions[sessionIndex].messages.first(where: { $0.id == messageID })?.role
    }

    private func removePermission(id: String) {
        permissionRequests.removeAll { $0.id == id }
        NotificationService.removeDelivered(id: id)
    }

    private func upsertPermission(_ request: PermissionRequest) {
        var request = request
        request.sessionTitle = sessions.first(where: { $0.id == request.sessionID })?.title ?? request.sessionID
        if let index = permissionRequests.firstIndex(where: { $0.id == request.id }) {
            permissionRequests[index] = request
        } else {
            permissionRequests.insert(request, at: 0)
            NotificationService.notifyPermissionRequested(request)
        }
    }

    private func markSession(_ sessionID: String, running: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        
        // Mutate a copy to ensure SwiftUI sees the change properly.
        var session = sessions[index]
        session.isRunning = running
        if !running {
            for messageIndex in session.messages.indices {
                session.messages[messageIndex].isStreaming = false
            }
        }
        sessions[index] = session
    }

    private func setSessionStatusNote(_ note: String?, for sessionID: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].statusNote = note
    }

    // Surface a session/prompt error inline in the transcript by attaching it to
    // the session's latest assistant message (the streaming stub for the prompt that
    // failed). When there is no assistant message yet, append a standalone error
    // bubble so the failure is still visible in the chat pane.
    private func attachSessionError(_ message: String, to sessionID: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var session = sessions[index]
        if let lastAssistant = session.messages.lastIndex(where: { $0.role == .assistant }) {
            session.messages[lastAssistant].errorMessage = message
            session.messages[lastAssistant].isStreaming = false
        } else {
            session.messages.append(
                TranscriptMessage(
                    id: "error-\(UUID().uuidString)",
                    role: .assistant,
                    parts: [],
                    date: Date(),
                    isStreaming: false,
                    errorMessage: message
                )
            )
        }
        sessions[index] = session
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

    private func saveSelectedSession() {
        guard let currentWorkspace, selectedSessionID != nil else { return }
        workspaceStore.saveLastSessionID(selectedSessionID, for: currentWorkspace)
    }

    private func appendActivity(kind: ActivityItem.Kind, title: String, detail: String, state: String, sessionID: String? = nil) {
        activity.insert(
            ActivityItem(id: UUID(), kind: kind, title: title, detail: detail, state: state, sessionID: sessionID),
            at: 0
        )
        trimActivity()
    }

    // Like appendActivity, but for rows that represent live state: if a row with the
    // same sourceID already exists, transition it in place (running → completed/failed)
    // instead of appending a new row. Keeps the existing id so SwiftUI preserves the
    // row (and its expansion state) rather than animating a fresh insert.
    private func upsertActivity(kind: ActivityItem.Kind, title: String, detail: String, state: String, sessionID: String?, sourceID: String, messageID: String? = nil) {
        if let index = activity.firstIndex(where: { $0.sourceID == sourceID && $0.kind == kind }) {
            var item = activity[index]
            item.title = title
            item.detail = detail
            item.state = state
            item.sessionID = sessionID
            item.messageID = messageID
            activity[index] = item
        } else {
            activity.insert(
                ActivityItem(id: UUID(), kind: kind, title: title, detail: detail, state: state, sessionID: sessionID, sourceID: sourceID, messageID: messageID),
                at: 0
            )
            trimActivity()
        }
    }

    func isMessageExpanded(_ messageID: String) -> Bool {
        expandedMessageIDs.contains(messageID)
    }

    func toggleMessageExpanded(_ messageID: String) {
        if expandedMessageIDs.contains(messageID) {
            expandedMessageIDs.remove(messageID)
        } else {
            expandedMessageIDs.insert(messageID)
        }
    }

    // Called when a sidebar activity row is clicked: expands the originating
    // message and asks the transcript to scroll to it.
    func revealMessage(_ messageID: String) {
        expandedMessageIDs.insert(messageID)
        scrollToMessageID = messageID
    }

    private func trimActivity() {
        if activity.count > activityLimit {
            activity = Array(activity.prefix(activityLimit))
        }
    }

    private func presentError(_ title: String, _ error: Error) {
        let message = "\(title): \(error.localizedDescription)"
        errorBanner = message
        appendActivity(kind: .runtime, title: title, detail: error.localizedDescription, state: "Failed")
    }
}
