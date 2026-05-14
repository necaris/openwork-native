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
                SidebarView()
            } content: {
                TranscriptView()
            } detail: {
                ActivityView()
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Open Folder") {
                    appState.pickWorkspace()
                }

                if appState.runtimeStatus == .running || appState.runtimeStatus == .starting {
                    Button("Stop OpenCode") {
                        appState.stopRuntime()
                    }
                } else {
                    Button("Start OpenCode") {
                        appState.startRuntime()
                    }
                    .disabled(appState.currentWorkspace == nil)
                }
            }
        }
    }
}
