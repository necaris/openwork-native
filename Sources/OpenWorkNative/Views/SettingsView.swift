import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("OpenCode Config") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model selection is read-only in OpenWork. Edit opencode.json outside the app, then restart OpenCode to reload providers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(appState.openCodeConfigURL?.path ?? "Choose a workspace to locate opencode.json")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)

                        Spacer()

                        Button("Reveal opencode.json") {
                            appState.revealOpenCodeConfig()
                        }
                        .disabled(appState.openCodeConfigURL == nil)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Model Providers") {
                ForEach(appState.providers) { provider in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(provider.name)
                            .font(.headline)
                        LabeledContent("Default model", value: provider.selectedModel)
                        LabeledContent("Available models", value: provider.models.joined(separator: ", "))
                        Text(provider.authStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 380)
        .padding()
    }
}
