import AppKit
import MarkdownUI
import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var appState: AppState
    @State private var prompt = ""
    @State private var promptHeight: CGFloat = 44
    @State private var editingMessageID: String?

    var body: some View {
        VStack(spacing: 0) {
            if let session = appState.sessions.first(where: { $0.id == appState.selectedSessionID }) {
                SessionStatusHeader(session: session)
                if let statusNote = session.statusNote {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(statusNote)
                            .lineLimit(2)
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let session = appState.sessions.first(where: { $0.id == appState.selectedSessionID }) {
                            ForEach(session.messages) { message in
                                MessageBubble(
                                    message: message,
                                    canRevert: appState.canRevert(to: message),
                                    onRetry: { appState.retryAssistantMessage(message.id) },
                                    onEdit: { beginEditing(message) }
                                )
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
                .onChange(of: appState.scrollToMessageID) {
                    guard let messageID = appState.scrollToMessageID else { return }
                    withAnimation {
                        proxy.scrollTo(messageID, anchor: .center)
                    }
                    appState.scrollToMessageID = nil
                }
            }

            Divider()

            if !matchingCommands.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(matchingCommands.prefix(8)) { item in
                            Button {
                                insertCommand(item)
                            } label: {
                                Label(
                                    item.slashCommand ?? item.name,
                                    systemImage: item.kind == .skill ? "sparkles" : "terminal"
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(item.kind == .skill ? .purple : nil)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }

            if editingMessageID != nil {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                    Text("Editing a previous message — sending will replace it and everything after.")
                        .lineLimit(2)
                    Spacer()
                    Button("Cancel") { cancelEditing() }
                        .controlSize(.small)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)
            }

            HStack(alignment: .bottom, spacing: 10) {
                PromptTextView(
                    text: $prompt,
                    height: $promptHeight,
                    placeholder: editingMessageID == nil ? "Ask OpenCode to work on this project" : "Edit your message…",
                    onSubmit: sendFromKeyboard
                )

                ComposerActions(
                    height: max(promptHeight, 52),
                    canSend: canSend,
                    isRunning: appState.selectedSession?.isRunning == true,
                    send: send,
                    stop: appState.stopSelectedSession
                )
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

    private var skillItems: [WorkspaceInventoryItem] {
        appState.inventory.filter { $0.kind == .skill }
    }

    private var matchingCommands: [WorkspaceInventoryItem] {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return [] }
        let query = String(trimmed.dropFirst()).lowercased()
        return (commandItems + skillItems).filter { item in
            query.isEmpty || item.name.lowercased().contains(query)
        }
    }

    private func insertCommand(_ command: WorkspaceInventoryItem) {
        guard let slashCommand = command.slashCommand else { return }
        prompt = "\(slashCommand) "
    }

    private func send() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let editingMessageID {
            appState.editAndResend(editingMessageID, newText: trimmed)
            self.editingMessageID = nil
        } else {
            appState.sendPrompt(prompt)
        }
        prompt = ""
    }

    private func sendFromKeyboard() -> Bool {
        guard canSend else { return false }
        send()
        return true
    }

    private func beginEditing(_ message: TranscriptMessage) {
        prompt = message.content
        editingMessageID = message.id
    }

    private func cancelEditing() {
        editingMessageID = nil
        prompt = ""
    }
}

private struct PromptTextView: View {
    @ScaledMetric var minHeight: CGFloat = 52
    @ScaledMetric var maxHeight: CGFloat = 156

    @Binding var text: String
    @Binding var height: CGFloat
    let placeholder: String
    let onSubmit: () -> Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            WrappingTextView(text: $text, height: $height, minHeight: minHeight, maxHeight: maxHeight, onSubmit: onSubmit)
                .frame(height: max(height, minHeight))

            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.75)
        }
    }
}

private struct ComposerActions: View {
    let height: CGFloat
    let canSend: Bool
    let isRunning: Bool
    let send: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: send) {
                Image(systemName: "paperplane.fill")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Send prompt (Command-Return)")
            .disabled(!canSend)

            Button(action: stop) {
                Image(systemName: "stop.fill")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .help("Stop session")
            .disabled(!isRunning)
        }
        .frame(width: 42, height: height)
    }
}

private struct WrappingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onSubmit: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = PromptNSTextView()
        textView.delegate = context.coordinator
        textView.onPlainReturn = { context.coordinator.submit() }
        textView.string = text
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: minHeight)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        textView.onPlainReturn = { context.coordinator.submit() }

        if textView.string != text {
            textView.string = text
        }

        Task { @MainActor in
            context.coordinator.recalculateHeight(in: scrollView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WrappingTextView
        weak var textView: PromptNSTextView?

        init(_ parent: WrappingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            if let scrollView = textView.enclosingScrollView {
                recalculateHeight(in: scrollView)
            }
        }

        func submit() -> Bool {
            parent.onSubmit()
        }

        func recalculateHeight(in scrollView: NSScrollView) {
            guard let textView, let textContainer = textView.textContainer, let layoutManager = textView.layoutManager else { return }

            let availableWidth = max(scrollView.contentSize.width, scrollView.bounds.width, 1)
            textView.frame.size.width = availableWidth
            textContainer.containerSize = NSSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)

            let usedHeight = layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2
            let nextHeight = min(max(ceil(usedHeight), parent.minHeight), parent.maxHeight)
            scrollView.hasVerticalScroller = usedHeight > parent.maxHeight

            if abs(parent.height - nextHeight) > 0.5 {
                parent.height = nextHeight
            }
        }
    }
}

private final class PromptNSTextView: NSTextView {
    var onPlainReturn: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let isShiftReturn = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)

        if isReturn, !isShiftReturn {
            if onPlainReturn?() == true {
                return
            }
            NSSound.beep()
            return
        }

        super.keyDown(with: event)
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
    @EnvironmentObject private var appState: AppState
    let session: OpenCodeSession

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Button("New Session", systemImage: "plus") {
                    appState.createSession()
                }
                .disabled(appState.currentWorkspace == nil || appState.runtimeStatus != .running)

                Divider()

                Picker("Session", selection: $appState.selectedSessionID) {
                    ForEach(appState.sessions) { availableSession in
                        Text(availableSession.title)
                            .tag(Optional(availableSession.id))
                    }
                }
            } label: {
                Label(session.title, systemImage: "bubble.left.and.bubble.right")
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .help("Switch session or create a new one")

            Button {
                appState.createSession()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .help("New Session")
            .disabled(appState.currentWorkspace == nil || appState.runtimeStatus != .running)

            if let model = appState.displayModel(for: session) {
                Text("\(model.modelID) · \(model.providerID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No model")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Menu("Change Model") {
                if appState.groupedAvailableModels.isEmpty {
                    Text("No models loaded")
                } else {
                    ForEach(appState.groupedAvailableModels, id: \.provider.id) { group in
                        Menu(group.provider.name) {
                            ForEach(group.modelIDs, id: \.self) { modelID in
                                Button(appState.modelDisplayName(modelID)) {
                                    appState.selectSessionModel(modelID, for: session)
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Open Model Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
            .font(.caption)
            .menuStyle(.button)
            .help("Choose the model for prompts sent in this session")
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
    @EnvironmentObject private var appState: AppState
    let message: TranscriptMessage
    let canRevert: Bool
    let onRetry: () -> Void
    let onEdit: () -> Void

    private var isCollapsed: Bool {
        message.isToolCallOnly && !appState.isMessageExpanded(message.id)
    }

    private var collapsedSummary: String {
        let count = message.toolCallCount
        return count == 1 ? "Tool call" : "\(count) tool calls"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(message.role.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                if message.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                if canRevert, message.role == .assistant {
                    Button {
                        onRetry()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Retry this turn")
                }
                if canRevert, message.role == .user {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit and resend")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy")
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

            if isCollapsed {
                Button {
                    withAnimation { appState.toggleMessageExpanded(message.id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(collapsedSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                if message.isToolCallOnly {
                    Button {
                        withAnimation { appState.toggleMessageExpanded(message.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(collapsedSummary)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                let parts = MessageContentParser.parse(message.content)
                ForEach(parts) { part in
                    switch part.kind {
                    case .markdown(let text):
                        Markdown(text)
                            .markdownTheme(message.role == .user ? .basic : .gitHub)
                            .markdownTextStyle {
                                if message.role == .user {
                                    FontSize(.em(1.15))
                                }
                            }
                            .markdownTextStyle(\.link) {
                                ForegroundColor(.accentColor)
                                UnderlineStyle(.single)
                            }
                            .markdownBlockStyle(\.codeBlock) { configuration in
                                CopyableCodeBlock(configuration: configuration)
                            }
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(nil)
                    case .details(let summary, let content):
                        DisclosureGroup(summary) {
                            Markdown(content)
                                .markdownTheme(.gitHub)
                                .markdownTextStyle(\.link) {
                                    ForegroundColor(.accentColor)
                                    UnderlineStyle(.single)
                                }
                                .markdownBlockStyle(\.codeBlock) { configuration in
                                    CopyableCodeBlock(configuration: configuration)
                                }
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(nil)
                                .padding(.top, 4)
                        }
                    }
                }
            }

            if let errorMessage = message.errorMessage, !errorMessage.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Error", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red.opacity(0.4), lineWidth: 0.75)
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

// MARK: - HTML/Details Parser

// MarkdownUI does not natively support HTML rendering (it explicitly maps .htmlBlock
// to plain text ParagraphViews). To cleanly render <details> blocks emitted by LLMs
// (e.g. for tool reasoning or lengthy traces) without breaking Markdown formatting
// or resorting to a heavy WKWebView, we use a lightweight linear scanner.
//
// This scanner splits the raw LLM output into .markdown and .details parts.
// .details parts map natively to SwiftUI DisclosureGroups, retaining Dynamic Type,
// VoiceOver support, and native animations, while the inner text remains fully Markdown.
// It safely ignores other HTML tags or angle brackets (like Swift generic <T>) that
// a full HTML DOM parser would trip over.
//
// `internal` (not `private`) so it can be exercised directly from tests via
// `@testable import` — access control cannot widen past a private enclosing type,
// so this lives at file scope rather than nested inside MessageBubble.
struct MessageContentPart: Identifiable, Equatable {
    let id: Int
    enum Kind: Equatable {
        case markdown(String)
        case details(summary: String, content: String)
    }
    let kind: Kind
}

enum MessageContentParser {
    static func parse(_ text: String) -> [MessageContentPart] {
        var parts: [MessageContentPart] = []
        var currentIndex = text.startIndex
        var idCounter = 0

        while currentIndex < text.endIndex {
            if let detailsRange = firstRealDetailsTag(in: text, from: currentIndex) {
                let beforeText = String(text[currentIndex..<detailsRange.lowerBound])
                if !beforeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(MessageContentPart(id: idCounter, kind: .markdown(beforeText)))
                    idCounter += 1
                }

                if let tagEndRange = text[detailsRange.upperBound...].range(of: ">") {
                    let contentStart = tagEndRange.upperBound
                    var searchIndex = contentStart
                    var depth = 1
                    var closingDetailsRange: Range<String.Index>? = nil

                    while searchIndex < text.endIndex {
                        let nextOpen = text[searchIndex...].range(of: "<details", options: [.caseInsensitive])
                        let nextClose = text[searchIndex...].range(of: "</details>", options: [.caseInsensitive])

                        if let close = nextClose {
                            if let open = nextOpen, open.lowerBound < close.lowerBound {
                                depth += 1
                                searchIndex = text.index(after: open.lowerBound)
                            } else {
                                depth -= 1
                                if depth == 0 {
                                    closingDetailsRange = close
                                    break
                                } else {
                                    searchIndex = close.upperBound
                                }
                            }
                        } else {
                            break
                        }
                    }

                    if let closeRange = closingDetailsRange {
                        let innerText = String(text[contentStart..<closeRange.lowerBound])
                        var summary = "Details"
                        var innerContent = innerText

                        if let summaryOpen = innerText.range(of: "<summary", options: [.caseInsensitive]),
                           let summaryTagEnd = innerText[summaryOpen.upperBound...].range(of: ">"),
                           let summaryClose = innerText[summaryTagEnd.upperBound...].range(of: "</summary>", options: [.caseInsensitive]) {

                            summary = String(innerText[summaryTagEnd.upperBound..<summaryClose.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            innerContent = String(innerText[summaryClose.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            innerContent = innerText.trimmingCharacters(in: .whitespacesAndNewlines)
                        }

                        parts.append(MessageContentPart(id: idCounter, kind: .details(summary: summary, content: innerContent)))
                        idCounter += 1
                        currentIndex = closeRange.upperBound
                    } else {
                        let remaining = String(text[detailsRange.lowerBound...])
                        parts.append(MessageContentPart(id: idCounter, kind: .markdown(remaining)))
                        idCounter += 1
                        break
                    }
                } else {
                    let remaining = String(text[detailsRange.lowerBound...])
                    parts.append(MessageContentPart(id: idCounter, kind: .markdown(remaining)))
                    idCounter += 1
                    break
                }
            } else {
                let remaining = String(text[currentIndex...])
                if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(MessageContentPart(id: idCounter, kind: .markdown(remaining)))
                    idCounter += 1
                }
                break
            }
        }

        if parts.isEmpty {
            parts.append(MessageContentPart(id: 0, kind: .markdown(text)))
        }

        return parts
    }

    // LLMs frequently mention `<details>` inside inline code as prose (e.g. explaining
    // how to write one), which is indistinguishable from a real opening tag by substring
    // search alone. Skip candidates that fall inside an odd-length run of backticks since
    // the start of their line, so only genuine HTML tags are treated as details blocks.
    private static func firstRealDetailsTag(in text: String, from start: String.Index) -> Range<String.Index>? {
        var searchFrom = start
        while let candidate = text[searchFrom...].range(of: "<details", options: [.caseInsensitive]) {
            if !isInsideInlineCode(text, at: candidate.lowerBound) {
                return candidate
            }
            searchFrom = candidate.upperBound
        }
        return nil
    }

    private static func isInsideInlineCode(_ text: String, at index: String.Index) -> Bool {
        let lineStart = text[text.startIndex..<index].lastIndex(of: "\n").map(text.index(after:)) ?? text.startIndex
        let backtickCount = text[lineStart..<index].filter { $0 == "`" }.count
        return backtickCount % 2 == 1
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
