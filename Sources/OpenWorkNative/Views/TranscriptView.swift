import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var appState: AppState
    @State private var prompt = ""

    var body: some View {
        VStack(spacing: 0) {
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
                .onChange(of: appState.selectedSession?.messages.count) { _ in
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

                Button("Send") {
                    appState.sendPrompt(prompt)
                    prompt = ""
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.selectedSession == nil)

                Button("Stop") {
                    appState.stopSelectedSession()
                }
                .disabled(appState.selectedSession?.isRunning != true)
            }
            .padding()
        }
        .navigationTitle(appState.selectedSession?.title ?? "Transcript")
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

            Text(message.content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(message.role == .user ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
