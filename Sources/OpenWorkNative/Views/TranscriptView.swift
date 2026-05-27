import MarkdownUI
import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var appState: AppState
    @State private var prompt = ""

    var body: some View {
        VStack(spacing: 0) {
            if let session = appState.selectedSession {
                SessionStatusHeader(session: session)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let session = appState.selectedSession {
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
                .onChange(of: appState.selectedSession?.messages.count) {
                    guard let lastMessage = appState.selectedSession?.messages.last else { return }
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }

            Divider()

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

    private func send() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.sendPrompt(prompt)
        prompt = ""
    }
}

private struct EmptyTranscriptView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Session")
                .font(.headline)
            Text("Open a workspace and create a session to start.")
                .foregroundStyle(.secondary)
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
                }
            }

            Markdown(message.content)
                .markdownTheme(.gitHub)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

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
