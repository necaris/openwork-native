import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            TranscriptView()
        } detail: {
            ActivityView()
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
