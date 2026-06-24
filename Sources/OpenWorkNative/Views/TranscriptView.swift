import AppKit
import MarkdownUI
import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var appState: AppState
    @State private var prompt = ""
    @State private var promptHeight = PromptTextView.minHeight

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

            HStack(alignment: .bottom, spacing: 10) {
                PromptTextView(
                    text: $prompt,
                    height: $promptHeight,
                    placeholder: "Ask OpenCode to work on this project",
                    onSubmit: sendFromKeyboard
                )

                Menu {
                    if !commandItems.isEmpty {
                        Section("Commands") {
                            ForEach(commandItems) { command in
                                Button(command.slashCommand ?? command.name) {
                                    insertCommand(command)
                                }
                            }
                        }
                    }
                    if !skillItems.isEmpty {
                        Section("Skills") {
                            ForEach(skillItems) { skill in
                                Button(skill.slashCommand ?? skill.name) {
                                    insertCommand(skill)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "terminal")
                }
                .keyboardShortcut("/", modifiers: .command)
                .help("Commands and skills")
                .disabled(commandItems.isEmpty && skillItems.isEmpty)

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
        appState.sendPrompt(prompt)
        prompt = ""
    }

    private func sendFromKeyboard() -> Bool {
        guard canSend else { return false }
        send()
        return true
    }
}

private struct PromptTextView: View {
    static let minHeight: CGFloat = 44
    private static let maxHeight: CGFloat = 132

    @Binding var text: String
    @Binding var height: CGFloat
    let placeholder: String
    let onSubmit: () -> Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            WrappingTextView(text: $text, height: $height, minHeight: Self.minHeight, maxHeight: Self.maxHeight, onSubmit: onSubmit)
                .frame(height: height)

            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
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
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 8)
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
                if appState.availableDefaultModelIDs.isEmpty {
                    Text("No models loaded")
                } else {
                    ForEach(appState.availableDefaultModelIDs, id: \.self) { modelID in
                        Button(modelID) {
                            appState.selectSessionModel(modelID, for: session)
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
