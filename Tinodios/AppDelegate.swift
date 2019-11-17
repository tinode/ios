//
//  AppDelegate.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Firebase
import Network
import SwiftWebSocket
import UIKit
import TinodiosDB

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var backgroundSessionCompletionHandler: (() -> Void)?
    // Network reachability.
    var nwReachability: Any!
    var pushNotificationsConfigured = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Utils.registerUserDefaults()
        let baseDb = BaseDb.getInstance()
        if baseDb.isReady {
            // When the app launch after user tap on notification (originally was not running / not in background).
            if let opts = launchOptions, let userInfo = opts[.remoteNotification] as? [String: Any],
                let topicName = userInfo["topic"] as? String, !topicName.isEmpty {
                UiUtils.routeToMessageVC(forTopic: topicName)
            } else {
                UiUtils.routeToChatListVC()
            }
        }
        // Try to connect and log in in the background.
        DispatchQueue.global(qos: .userInitiated).async {
            if let token = Utils.getAuthToken(), !token.isEmpty, let userName = Utils.getSavedLoginUserName(), !userName.isEmpty {
                let tinode = Cache.getTinode()
                var success = false
                do {
                    tinode.setAutoLoginWithToken(token: token)
                    _ = try tinode.connectDefault()?.getResult()
                    let msg = try tinode.loginToken(token: token, creds: nil)?.getResult()
                    if let code = msg?.ctrl?.code {
                        // Assuming success by default.
                        success = true
                        switch code {
                        case 0..<300:
                            Cache.log.info("AppDelegate - login successful for: %@", tinode.myUid!)
                            if tinode.authToken != token {
                                Utils.saveAuthToken(for: userName, token: tinode.authToken)
                            }
                        case 409:
                            Cache.log.info("AppDelegate - already authenticated.")
                        case 500..<600:
                            Cache.log.error("AppDelegate - server error on login: %d", code)
                        default:
                            success = false
                        }
                    }
                } catch SwiftWebSocket.WebSocketError.network(let e)  {
                    // No network connection.
                    Cache.log.debug("AppDelegate [network] - could not connect to Tinode: %@", e)
                    success = true
                } catch {
                    Cache.log.error("AppDelegate - failed to automatically login to Tinode: %@", error.localizedDescription)
                }
                if !success {
                    _ = tinode.logout()
                    UiUtils.routeToLoginVC()
                }
            }
        }
        if #available(iOS 12.0, *) {
            let reachability = NWPathMonitor()
            reachability.start(queue: DispatchQueue.global(qos: .background))
            reachability.pathUpdateHandler = { path in
                let tinode = Cache.getTinode()
                if path.status == .satisfied, !tinode.isConnected {
                    tinode.reconnectNow()
                }
            }
            self.nwReachability = reachability
        }  // else TODO.
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        backgroundSessionCompletionHandler = completionHandler
        // Instantiate large file helper.
        let _ = Cache.getLargeFileHelper(withIdentifier: identifier)
    }

    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        application.applicationIconBadgeNumber = Cache.totalUnreadCount()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
    }

    func applicationWillTerminate(_ application: UIApplication) {
        application.applicationIconBadgeNumber = Cache.totalUnreadCount()
    }
}
@available(iOS 10.0, *)
extension AppDelegate: UNUserNotificationCenterDelegate {
    // Called when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        guard let topicName = userInfo["topic"] as? String, !topicName.isEmpty else { return }
        if let messageVC = UiUtils.topViewController(rootViewController: UIApplication.shared.keyWindow?.rootViewController) as? MessageViewController, messageVC.topicName == topicName {
            // We are already in the correct topic. Do not present the notification.
            completionHandler([])
        } else {
            completionHandler([.alert, .badge, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        print(response)
        let userInfo = response.notification.request.content.userInfo
        defer { completionHandler() }
        guard let topicName = userInfo["topic"] as? String, !topicName.isEmpty else { return }
        UiUtils.routeToMessageVC(forTopic: topicName)
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceive remoteMessage: MessagingRemoteMessage) {
        Cache.log.info("Received data message: %@", remoteMessage.appData)
    }
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String) {
        // Update token. Send to the app server.
        print("Firebase registration token: \(fcmToken)")
        Cache.getTinode().setDeviceToken(token: fcmToken)
    }
}
