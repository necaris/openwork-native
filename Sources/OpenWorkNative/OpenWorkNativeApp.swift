import AppKit
import SwiftUI

@main
struct OpenWorkNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1080, minHeight: 680)
                .onAppear { appDelegate.appState = appState }
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationService.requestAuthorization()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.app.log("applicationWillTerminate — stopping OpenCode runtime")
        appState?.stopRuntime()
    }
}
