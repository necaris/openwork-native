import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Model Providers") {
                ForEach(appState.providers) { provider in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(provider.name)
                            .font(.headline)
                        Picker("Default model", selection: .constant(provider.selectedModel)) {
                            ForEach(provider.models, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        Text(provider.authStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 320)
        .padding()
    }
}
