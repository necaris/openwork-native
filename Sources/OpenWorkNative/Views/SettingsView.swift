import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("OpenCode Config") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Default model selection is persisted through OpenCode global config. MCP configuration remains read-only in OpenWork; edit OpenCode config outside the app, then restart OpenCode to reload MCPs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(appState.openCodeConfigURL?.path ?? "Choose a workspace to locate OpenCode config")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)

                        Spacer()

                        Button("Reveal OpenCode Config") {
                            appState.revealOpenCodeConfig()
                        }
                        .disabled(appState.openCodeConfigURL == nil)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Default Model") {
                Picker("Model", selection: Binding(
                    get: { appState.selectedDefaultModelID ?? "" },
                    set: { appState.selectDefaultModel($0) }
                )) {
                    if appState.selectedDefaultModelID == nil {
                        Text("No default model selected").tag("")
                    }
                    ForEach(appState.availableDefaultModelIDs, id: \.self) { modelID in
                        Text(modelID).tag(modelID)
                    }
                }
                .pickerStyle(.menu)
                .disabled(appState.runtimeStatus != .running || appState.availableDefaultModelIDs.isEmpty || appState.isUpdatingDefaultModel)

                if appState.isUpdatingDefaultModel {
                    ProgressView("Updating default model…")
                        .controlSize(.small)
                } else if appState.runtimeStatus != .running {
                    Text("Start OpenCode to load and change available models.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
