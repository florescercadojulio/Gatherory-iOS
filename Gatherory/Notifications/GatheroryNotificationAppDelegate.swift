import FirebaseCore
import FirebaseMessaging
import UIKit
import UserNotifications

final class GatheroryNotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    static weak var controller: NotificationController?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        guard FCMRuntimeConfiguration.isConfigured else { return true }
        FirebaseApp.configure()
        Messaging.messaging().isAutoInitEnabled = false
        Messaging.messaging().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard FCMRuntimeConfiguration.isConfigured else { return }
        Messaging.messaging().apnsToken = deviceToken
        Task { @MainActor in
            guard let token = try? await FirebaseNotificationTokenProvider().currentToken() else { return }
            await Self.controller?.receiveFCMToken(token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Push remains unavailable on this installation; local planning still works.
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in await Self.controller?.receiveFCMToken(fcmToken) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            let allowed = await Self.controller?.receiveForegroundNotification(notification.request.content.userInfo) ?? false
            completionHandler(allowed ? [.banner, .sound] : [])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            Self.controller?.receiveNotificationTap(userInfo)
            completionHandler()
        }
    }
}
