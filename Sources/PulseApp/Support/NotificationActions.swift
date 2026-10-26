import AppKit
import Foundation
import UserNotifications

/// "Export finished" notifications carry the file (#439): clicking one, or its Show in Finder button,
/// reveals the export.
final class NotificationActions: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationActions()
    static let exportCategory = "pulse.export"
    static let revealAction = "pulse.reveal"

    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reveal = UNNotificationAction(identifier: Self.revealAction, title: "Show in Finder", options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.exportCategory, actions: [reveal], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let path = response.notification.request.content.userInfo["path"] as? String, FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
