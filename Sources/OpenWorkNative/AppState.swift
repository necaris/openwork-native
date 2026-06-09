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
    @Published var permissionRequests: [PermissionRequest] = []
    @Published var changedFiles: [ChangedFile] = []
    @Published var inventory: [WorkspaceInventoryItem] = []
    @Published var showingManagementSheet = false
    @Published var isInventoryInspectorVisible = false
    @Published var providers: [ModelProvider] = [
        ModelProvider(
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
    private let activityLimit = 80
    var client: OpenCodeClient?
    private var eventTask: Task<Void, Never>?
    private var sessionMessageTask: Task<Void, Never>?
    private var restoredSessionID: String?

    var selectedSession: OpenCodeSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    var openCodeConfigURL: URL? {
        guard let currentWorkspace else { return nil }
        return URL(fileURLWithPath: currentWorkspace.path).appendingPathComponent("opencode.json")
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
            TranscriptMessage(id: "local-user-\(UUID().uuidString)", role: .user, parts: [TranscriptMessagePart(id: "local-part", type: "text", text: trimmedPrompt)], date: Date(), isStreaming: false)
        )
        sessions[index].messages.append(
            TranscriptMessage(id: "stream-\(UUID().uuidString)", role: .assistant, parts: [], date: Date(), isStreaming: true)
        )
        sessions[index].isRunning = true
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

    func revealInventoryItem(_ item: WorkspaceInventoryItem) {
        guard let workspacePath = currentWorkspace?.path else { return }
        let url = URL(fileURLWithPath: workspacePath).appendingPathComponent(item.path)
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
            errorBanner = "No opencode.json found in this workspace. Create or edit it outside OpenWork, then restart OpenCode."
        }
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
        inventory = await inventoryService.loadInventory(in: currentWorkspace)
    }

    private func loadProviders() async {
        do {
            if let loadedProviders = try await client?.loadProviders(), !loadedProviders.isEmpty {
                providers = loadedProviders
                AppLog.state.log("Loaded \(loadedProviders.count, privacy: .public) provider(s)")
            }
        } catch {
            let message = error.localizedDescription
            errorBanner = "OpenCode model/provider configuration needs attention. Edit opencode.json outside OpenWork, then restart OpenCode."
            providers = [ModelProvider(name: "OpenCode", models: ["Unavailable"], selectedModel: "Unavailable", authStatus: message)]
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
                markSession(sessionID, running: event.sessionStatus == "busy" && event.type != "session.idle")
            }
        case "session.updated":
            applySessionUpdated(event)
        case "session.next.model.switched":
            applyModelSwitched(event)
        case "session.next.agent.switched":
            if let agent = event.properties["agent"]?.stringValue {
                appendActivity(kind: .runtime, title: "Agent switched", detail: agent, state: agent)
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
        } else if partType == "tool_call" {
            let name = event.properties["part"]?.objectValue?["toolCall"]?.objectValue?["name"]?.stringValue ?? "tool"
            upsertMessage(sessionID: sessionID, messageID: messageID, role: role, part: TranscriptMessagePart(id: partID, type: partType, text: name), streaming: streaming, isDelta: false)
            let tool = event.properties["part"]?.objectValue?["tool"]?.stringValue ?? name
            let state = event.properties["part"]?.objectValue?["state"]?.objectValue?["status"]?.stringValue ?? "running"
            appendActivity(kind: .tool, title: tool, detail: messageID, state: state)
        } else if partType == "tool_result" {
            let output = event.properties["part"]?.objectValue?["toolResult"]?.objectValue?["text"]?.stringValue ?? "No output"
            upsertMessage(sessionID: sessionID, messageID: messageID, role: role, part: TranscriptMessagePart(id: partID, type: partType, text: output), streaming: streaming, isDelta: false)
        } else if partType == "tool" {
            let tool = event.properties["part"]?.objectValue?["tool"]?.stringValue ?? "Tool"
            let state = event.properties["part"]?.objectValue?["state"]?.objectValue?["status"]?.stringValue ?? "running"
            appendActivity(kind: .tool, title: tool, detail: messageID, state: state)
        }
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
            appendActivity(kind: .runtime, title: "Model switched", detail: detail, state: modelID)
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

    private func writeDebugLog(for session: OpenCodeSession) {
        guard let workspace = currentWorkspace else { return }
        let logURL = URL(fileURLWithPath: workspace.path).appendingPathComponent("chat_debug_log.txt")
        var log = "=== [\(Date())] Session: \(session.id) ===\n"
        log += "Running: \(session.isRunning)\n\n"
        for msg in session.messages {
            log += "[\(msg.role.rawValue)] (id: \(msg.id), streaming: \(msg.isStreaming))\n"
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

    private func appendActivity(kind: ActivityItem.Kind, title: String, detail: String, state: String) {
        activity.insert(
            ActivityItem(id: UUID(), kind: kind, title: title, detail: detail, state: state),
            at: 0
        )
        trimActivity()
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
