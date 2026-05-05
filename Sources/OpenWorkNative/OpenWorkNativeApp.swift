import SwiftUI

@main
struct OpenWorkNativeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1080, minHeight: 680)
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
