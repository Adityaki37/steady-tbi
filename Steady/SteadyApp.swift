import SwiftUI
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main struct SteadyApp: App {
    @StateObject private var store = AppStore()
    private let notificationDelegate = NotificationDelegate()
    init() { UNUserNotificationCenter.current().delegate = notificationDelegate }
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store).tint(Color.accentColor)
                .alert(item: $store.notice) { notice in Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK"))) }
        }
    }
}
