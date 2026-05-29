import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if let error = appState.errorBanner {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .lineLimit(2)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.red)
            }

            NavigationSplitView {
                InventoryView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 400)
            } detail: {
                TranscriptView()
                    .inspector(isPresented: .constant(true)) {
                        ActivityView()
                            .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
                    }
            }
        }
        .sheet(isPresented: $appState.showingManagementSheet) {
            ManagementView()
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: {
                    appState.showingManagementSheet = true
                }) {
                    Label("Workspaces & Sessions", systemImage: "list.bullet.rectangle")
                }
                .help("Manage Workspaces & Sessions")

                Button(action: {
                    appState.pickWorkspace()
                }) {
                    Label("Open Workspace", systemImage: "folder.badge.plus")
                }
                .help("Open Workspace")

                Button(action: {
                    appState.createSession()
                }) {
                    Label("New Session", systemImage: "square.and.pencil")
                }
                .disabled(appState.currentWorkspace == nil || appState.runtimeStatus != .running)
                .help("New Session")

                if appState.runtimeStatus == .running || appState.runtimeStatus == .starting {
                    Button(action: {
                        appState.stopRuntime()
                    }) {
                        Label("Stop OpenCode", systemImage: "stop.circle")
                    }
                    .help("Stop OpenCode")
                } else if appState.runtimeStatus == .failed {
                    Button(action: {
                        appState.startRuntime()
                    }) {
                        Label("Retry OpenCode", systemImage: "arrow.clockwise.circle")
                    }
                    .disabled(appState.currentWorkspace == nil || !appState.openCodeAvailable)
                    .help("Retry OpenCode")
                } else {
                    Button(action: {
                        appState.startRuntime()
                    }) {
                        Label("Start OpenCode", systemImage: "play.circle")
                    }
                    .disabled(appState.currentWorkspace == nil || !appState.openCodeAvailable)
                    .help("Start OpenCode")
                }
            }
        }
    }
}
