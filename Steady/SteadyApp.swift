import SwiftUI
import UIKit
import UserNotifications

// Shared handoff for the APNs device token. The app delegate captures the token
// asynchronously from the system; the account layer reads it once the user is
// signed in and uploads it to the backend. The local single-device demo never
// needs this and keeps working with no account and no token.
@MainActor final class PushRegistrar: ObservableObject {
    static let shared = PushRegistrar()
    @Published private(set) var deviceToken: String?
    private init() {}
    func update(_ hexToken: String) { deviceToken = hexToken }
    func requestAuthorizationAndRegister() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Calm foreground presentation; the same banner style used by the local demo.
        completionHandler([.banner, .sound])
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in PushRegistrar.shared.update(hex) }
    }
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Registration can fail without a paid Apple Developer account + APNs setup.
        // The app still works; cross-device delivery simply stays unavailable and the
        // foreground refresh remains the fallback.
    }
}

@main struct SteadyApp: App {
    @StateObject private var store = AppStore()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let notificationDelegate = NotificationDelegate()
    init() { UNUserNotificationCenter.current().delegate = notificationDelegate }
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store).tint(Color.accentColor)
                .alert(item: $store.notice) { notice in Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK"))) }
        }
    }
}
