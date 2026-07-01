import Foundation
import UserNotifications

/// Posts OS-level notifications for events the user needs to act on while the app
/// isn't focused (e.g. a permission request blocking a session). The app runs
/// unsandboxed and out of a properly bundled .app (see maskfile.md's `app`/`install`
/// tasks), so local notifications work without additional entitlements — but
/// `UNUserNotificationCenter.current()` throws an uncaught NSException when the process
/// has no bundle identifier (e.g. `swift run`), so every entry point here is a no-op
/// unless launched from a real .app bundle.
struct NotificationService {
    private static var isRunningFromAppBundle: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static func requestAuthorization() {
        guard isRunningFromAppBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                AppLog.app.log("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func notifyPermissionRequested(_ request: PermissionRequest) {
        guard isRunningFromAppBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = "Permission needed"
        content.body = "\(request.sessionTitle): \(request.action)"
        content.sound = .default
        let notificationRequest = UNNotificationRequest(identifier: "permission-\(request.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(notificationRequest)
    }

    static func removeDelivered(id: String) {
        guard isRunningFromAppBundle else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["permission-\(id)"])
    }
}
