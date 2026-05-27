import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: $appState.selectedSessionID) {
            Section("Workspace") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.currentWorkspace?.displayName ?? "No workspace")
                        .font(.headline)
                    Text(appState.runtimeDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Label(appState.runtimeStatus.rawValue, systemImage: runtimeIcon)
                        .font(.caption)
                        .foregroundStyle(runtimeColor)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.openCodeAvailable ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(appState.openCodeAvailable ? "OpenCode available" : "OpenCode not found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if !appState.recentWorkspaces.isEmpty {
                Section("Recent") {
                    ForEach(appState.recentWorkspaces) { workspace in
                        Button {
                            appState.openWorkspace(at: URL(fileURLWithPath: workspace.path))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(workspace.displayName)
                                Text(workspace.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    appState.createSession()
                } label: {
                    Label("New Session", systemImage: "plus")
                }
                .disabled(appState.currentWorkspace == nil)
            }

            Section("Sessions") {
                ForEach(appState.sessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.headline)
                        Text(session.createdAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(session.id)
                }
            }
        }
        .navigationTitle("OpenWork")
    }

    private var runtimeIcon: String {
        switch appState.runtimeStatus {
        case .stopped: "pause.circle"
        case .starting: "clock"
        case .running: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var runtimeColor: Color {
        switch appState.runtimeStatus {
        case .stopped: .secondary
        case .starting: .orange
        case .running: .green
        case .failed: .red
        }
    }
}
