//
//  AppDelegate.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Firebase
import Network
import UIKit
import TinodeSDK
import TinodiosDB

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var backgroundSessionCompletionHandler: (() -> Void)?
    // Network reachability.
    var nwReachability: Any!
    var pushNotificationsConfigured = false
    var appIsStarting: Bool = false

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
            if !Utils.connectAndLoginSync() {
                Cache.getTinode().logout()
                UiUtils.routeToLoginVC()
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
        self.appIsStarting = false
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        self.appIsStarting = false
        application.applicationIconBadgeNumber = Cache.totalUnreadCount()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        self.appIsStarting = true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        self.appIsStarting = false
    }

    func applicationWillTerminate(_ application: UIApplication) {
        application.applicationIconBadgeNumber = Cache.totalUnreadCount()
    }

    // Synchronously connects to topic |topicName| and fetches its messages
    // if the last received message was prior to |seq|.
    @discardableResult
    private func fetchData(for topicName: String, seq: Int) -> UIBackgroundFetchResult {
        let tinode = Cache.getTinode()
        var topic: DefaultComTopic
        var builder: DefaultComTopic.MetaGetBuilder
        if !tinode.isTopicTracked(topicName: topicName) {
            // New topic. Create it.
            guard let t = tinode.createAndPresistTopic(withName: topicName, with: nil) as? DefaultComTopic else {
                return .failed
            }
            topic = t
            builder = topic.getMetaGetBuilder().withDesc().withSub()
        } else {
            // Existing topic.
            guard let t = tinode.getTopic(topicName: topicName) as? DefaultComTopic else { return .failed }
            topic = t
            builder = topic.getMetaGetBuilder()
        }

        if (topic.recv ?? 0) >= seq {
            return .noData
        }
        defer {
            if topic.attached {
                topic.leave()
            }
        }
        if let msg = try? topic.subscribe(
            set: nil,
            get: builder
                .withLaterData(limit: 10)
                .withDel().build())?.getResult(), (msg.ctrl?.code ?? 500) < 300 {
            return .newData
        }
        return .failed
    }

    // Application woken up in the background (e.g. for data fetch).
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let state = application.applicationState
        guard let topicName = userInfo["topic"] as? String, !topicName.isEmpty, let seqStr = userInfo["seq"] as? String, let seq = Int(seqStr) else {
            completionHandler(.failed)
            return
        }
        if state == .background || (state == .inactive && !self.appIsStarting) {
            // Fetch data in the background.
            if Cache.getTinode().isConnectionAuthenticated || Utils.connectAndLoginSync() {
                completionHandler(fetchData(for: topicName, seq: seq))
            } else {
                completionHandler(.failed)
            }
        } else if state == .inactive && self.appIsStarting {
            // User tapped notification.
            completionHandler(.newData)
        } else {
            // App is active.
            completionHandler(.noData)
        }
    }

    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let url = userActivity.webpageURL,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return false
        }
        // TODO: support 3rd party urls.
        if (components.host?.hasSuffix("tinode.co") ?? false) {
            // Start the app.
            return true
        }
        return false
    }
}

@available(iOS 10.0, *)
extension AppDelegate: UNUserNotificationCenterDelegate {
    // Called when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        guard let topicName = userInfo["topic"] as? String, !topicName.isEmpty, let seqStr = userInfo["seq"] as? String, let seq = Int(seqStr) else { return }
        if let messageVC = UiUtils.topViewController(rootViewController: UIApplication.shared.keyWindow?.rootViewController) as? MessageViewController, messageVC.topicName == topicName {
            // We are already in the correct topic. Do not present the notification.
            completionHandler([])
        } else {
            DispatchQueue.global(qos: .background).async {
                self.fetchData(for: topicName, seq: seq)
            }
            completionHandler([.alert, .badge, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        print(response)
        let userInfo = response.notification.request.content.userInfo
        defer { completionHandler() }
        guard let topicName = userInfo["topic"] as? String, !topicName.isEmpty else { return }
        if Cache.getTinode().isConnectionAuthenticated {
            UiUtils.routeToMessageVC(forTopic: topicName)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            if !Utils.connectAndLoginSync() {
                Cache.getTinode().logout()
                UiUtils.routeToLoginVC()
            } else {
                UiUtils.routeToMessageVC(forTopic: topicName)
            }
        }
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
