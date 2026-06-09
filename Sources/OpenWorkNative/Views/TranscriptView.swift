import MarkdownUI
import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var appState: AppState
    @State private var prompt = ""

    var body: some View {
        VStack(spacing: 0) {
            if let session = appState.sessions.first(where: { $0.id == appState.selectedSessionID }) {
                SessionStatusHeader(session: session)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let session = appState.sessions.first(where: { $0.id == appState.selectedSessionID }) {
                            ForEach(session.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        } else {
                            EmptyTranscriptView()
                        }
                    }
                    .padding()
                }
                .onChange(of: appState.sessions.first(where: { $0.id == appState.selectedSessionID })?.messages.count) {
                    guard let lastMessage = appState.sessions.first(where: { $0.id == appState.selectedSessionID })?.messages.last else { return }
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            if !matchingCommands.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(matchingCommands.prefix(8)) { command in
                            Button(command.slashCommand ?? command.name) {
                                insertCommand(command)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask OpenCode to work on this project", text: $prompt, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.roundedBorder)
                    .onKeyPress(.return) {
                        if NSEvent.modifierFlags.contains(.shift) { return .ignored }
                        if canSend {
                            send()
                            return .handled
                        }
                        return .ignored
                    }

                Menu {
                    ForEach(commandItems) { command in
                        Button(command.slashCommand ?? command.name) {
                            insertCommand(command)
                        }
                    }
                } label: {
                    Image(systemName: "terminal")
                }
                .keyboardShortcut("/", modifiers: .command)
                .help("Commands")
                .disabled(commandItems.isEmpty)

                Button("Send") {
                    send()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend)

                Button("Stop") {
                    appState.stopSelectedSession()
                }
                .disabled(appState.selectedSession?.isRunning != true)
            }
            .padding()
        }
        .navigationTitle(appState.selectedSession?.title ?? "Transcript")
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && appState.selectedSession != nil
    }

    private var commandItems: [WorkspaceInventoryItem] {
        appState.inventory.filter { $0.kind == .command }
    }

    private var matchingCommands: [WorkspaceInventoryItem] {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return [] }
        let query = String(trimmed.dropFirst()).lowercased()
        return commandItems.filter { command in
            query.isEmpty || command.name.lowercased().contains(query)
        }
    }

    private func insertCommand(_ command: WorkspaceInventoryItem) {
        guard let slashCommand = command.slashCommand else { return }
        prompt = "\(slashCommand) "
    }

    private func send() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.sendPrompt(prompt)
        prompt = ""
    }
}

private struct EmptyTranscriptView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("OpenWork")
                .font(.title2)
                .fontWeight(.medium)
            Text("Select or create a workspace to begin.")
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                Button(action: {
                    appState.pickWorkspace()
                }) {
                    Label("Open Workspace", systemImage: "folder")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: {
                    appState.showingManagementSheet = true
                }) {
                    Label("View Recents", systemImage: "clock")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(appState.recentWorkspaces.isEmpty)
            }
            .padding(.top, 8)
            
            if appState.currentWorkspace != nil {
                Divider().frame(width: 200).padding(.vertical, 8)
                Button(action: {
                    appState.createSession()
                }) {
                    Label("New Session", systemImage: "square.and.pencil")
                }
                .disabled(appState.runtimeStatus != .running)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}

private struct SessionStatusHeader: View {
    let session: OpenCodeSession

    var body: some View {
        HStack(spacing: 12) {
            if let model = session.model {
                Text("\(model.modelID) · \(model.providerID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No model")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text("\(CountFormatter.abbreviated(session.tokens.total)) tokens")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .help(tokenTooltip)
            Text(CountFormatter.usd(session.cost))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var tokenTooltip: String {
        let t = session.tokens
        return "input \(t.input) · output \(t.output) · reasoning \(t.reasoning) · cache read \(t.cacheRead) / write \(t.cacheWrite)"
    }
}

private struct MessageBubble: View {
    let message: TranscriptMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.role.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                if message.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }

            if let thinking = message.thinking, !thinking.isEmpty {
                DisclosureGroup("Thinking") {
                    Text(thinking)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(nil)
                }
            }

            Markdown(message.content)
                .markdownTheme(message.role == .user ? .basic : .gitHub)
                .markdownBlockStyle(\.codeBlock) { configuration in
                    CopyableCodeBlock(configuration: configuration)
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(nil)

            if let errorMessage = message.errorMessage, !errorMessage.isEmpty {
                DisclosureGroup {
                    Text(errorMessage)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Upstream error", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if message.role == .assistant, let footer = assistantFooter {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .background(message.role == .user ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var assistantFooter: String? {
        var parts: [String] = []
        if let model = message.model { parts.append(model.modelID) }
        if let tokens = message.tokens {
            parts.append("\(CountFormatter.abbreviated(tokens.input)) in / \(CountFormatter.abbreviated(tokens.output)) out")
        }
        if let cost = message.cost { parts.append(CountFormatter.usd(cost)) }
        if let latency = message.latency, latency > 0 { parts.append(CountFormatter.latency(latency)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct CopyableCodeBlock: View {
    let configuration: CodeBlockConfiguration
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(languageLabel)
                    .font(.caption.monospaced())
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Button {
                    copyCode()
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help(copied ? "Copied" : "Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.225))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .markdownMargin(top: 0, bottom: 12)
    }

    private var languageLabel: String {
        guard let language = configuration.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty else {
            return "plain text"
        }
        return language
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configuration.content, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            copied = false
        }
    }
}
