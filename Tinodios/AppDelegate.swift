//
//  AppDelegate.swift
//  ios
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import Firebase
import PushKit
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
    // Video call event listener.
    var callListener = CallEventListener()

    var voipRegistry: PKPushRegistry!

    // Video call event listener.
    class CallEventListener: TinodeEventListener {
        func onInfoMessage(info: MsgServerInfo?) {
            guard let info = info, info.what == "call" else { return }
            if info.event == MsgServerData.WebRTC.kAccepted.rawValue {
                guard let seq = info.seq, let topic = info.topic else { return }
                Cache.callManager.dismissIncomingCall(onTopic: topic, withSeqId: seq)
            }
        }
        func onDataMessage(data: MsgServerData?) {
            let tinode = Cache.tinode
            // The message is from a peer.
            guard let data = data, !tinode.isMe(uid: data.from), let seqId = data.seq, let originator = data.from,
                  // It is a video call message.
                  MsgServerData.parseWebRTC(from: data.head?["webrtc"]?.asString()) == .kStarted,
                  let topicName = data.topic, let topic = tinode.getTopic(topicName: topicName) else { return }

            // Check if we have a later version of the message (which means the call
            // has been not yet been either accepted or finished).
            guard let msg = topic.getMessage(byEffectiveSeq: seqId) as? StoredMessage,
                  MsgServerData.parseWebRTC(from: msg.head?["webrtc"]?.asString()) == .kStarted else { return }

            // It is a legit call.
            let backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
            DispatchQueue.main.async {
                Cache.callManager.displayIncomingCall(uuid: UUID(), onTopic: topic.name, originatingFrom: originator, withSeqId: seqId) { err in
                    if let err = err {
                        Cache.log.error("Unable to take the call: %@", err.localizedDescription)
                    }
                    UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
                }
            }
        }
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        SharedUtils.registerUserDefaults()
        let baseDb = BaseDb.sharedInstance
        if baseDb.isReady {
            // When the app launch after user tap on notification (originally was not running / not in background).
            if let opts = launchOptions, let userInfo = opts[.remoteNotification] as? [String: Any],
                let topicName = userInfo["topic"] as? String, !topicName.isEmpty {
                UiUtils.routeToMessageVC(forTopic: topicName)
            } else {
                UiUtils.routeToChatListVC()
            }
        }

        registerForVoip()

        // Try to connect and login in the background.
        DispatchQueue.global(qos: .userInitiated).async {
            if !SharedUtils.connectAndLoginSync(using: Cache.tinode, inBackground: false) {
                UiUtils.logoutAndRouteToLoginVC()
            }
        }
        Cache.tinode.addListener(self.callListener)
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + .seconds(10)) {
            let reachability = NWPathMonitor()
            reachability.start(queue: DispatchQueue.global(qos: .background))
            reachability.pathUpdateHandler = { path in
                let tinode = Cache.tinode
                if path.status == .satisfied, !tinode.isConnected {
                    Cache.log.info("NWPathMonitor: network available - reconnecting")
                    tinode.reconnectNow(interactively: false, reset: false)
                }
            }
            self.nwReachability = reachability
        }
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        backgroundSessionCompletionHandler = completionHandler
        // Instantiate large file helper.
        _ = Cache.getLargeFileHelper(withIdentifier: identifier)
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

    // Notification received. Process it.
    // Application woken up in the background (e.g. for data fetch).
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let state = application.applicationState
        guard let topicName = userInfo["topic"] as? String, !topicName.isEmpty else {
            completionHandler(.failed)
            return
        }
        if state == .background || (state == .inactive && !self.appIsStarting) {
            let what = userInfo["what"] as? String
            if what == nil || what == "msg" {
                // New message.
                guard let seq = Int(userInfo["seq"] as? String ?? ""), seq > 0 else {
                    completionHandler(.failed)
                    return
                }
                var keepConnection = false
                if userInfo["webrtc"] != nil {
                    // Video call. Fetch related messages.
                    keepConnection = true
                }
                // Fetch data in the background.
                completionHandler(SharedUtils.fetchData(using: Cache.tinode, for: topicName, seq: seq, keepConnection: keepConnection))
            } else if what == "sub" {
                // New subscription.
                completionHandler(SharedUtils.fetchDesc(using: Cache.tinode, for: topicName))
            } else if what == "read" {
                // Read notification.
                if let seq = Int(userInfo["seq"] as? String ?? ""), seq > 0 {
                    completionHandler(SharedUtils.updateRead(using: Cache.tinode, for: topicName, seq: seq))
                }
            } else {
                Cache.log.error("Invalid 'what' value ['%@'] in push notification for topic '%@'", what!, topicName)
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

    // Tapped on a web link. See if it's an app link.
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let url = userActivity.webpageURL,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return false
        }
        // TODO: support 3rd party urls.
        if components.host?.hasSuffix("tinode.co") ?? false {
            // Start the app.
            return true
        }
        return false
    }

    func registerForVoip() {
        self.voipRegistry = PKPushRegistry(queue: nil)
        self.voipRegistry.delegate = self
        self.voipRegistry.desiredPushTypes = [.voIP]
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Notification received. Process it.
    // Called when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        let what = userInfo["what"] as? String
        // Only handling "msg" notifications. New subscriptions ("sub" notifications) in the foreground
        // will be handled automatically by Tinode SDK.
        guard let topicName = userInfo["topic"] as? String, !topicName.isEmpty,
            what == nil || what == "msg", let seq = Int(userInfo["seq"] as? String ?? "") else { return }

        if let messageVC = UiUtils.topViewController(rootViewController: UIApplication.shared.keyWindow?.rootViewController) as? MessageViewController, messageVC.topicName == topicName {
            // We are already in the correct topic. Do not present the notification.
            completionHandler([])
        } else {
            DispatchQueue.global(qos: .background).async {
                SharedUtils.fetchData(using: Cache.tinode, for: topicName, seq: seq, keepConnection: false)
            }
            // If the push notification is either silent or a video call related, do not present the alert.
            let suppressNotification = userInfo["silent"] as? String == "true" || userInfo["webrtc"] != nil
            completionHandler(!suppressNotification ? [.alert, .badge, .sound] : [])
        }
    }

    // User tapped on notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        defer { completionHandler() }
        guard let topicName = userInfo["topic"] as? String, !topicName.isEmpty else { return }
        let tinode = Cache.tinode
        if tinode.isConnectionAuthenticated {
            UiUtils.routeToMessageVC(forTopic: topicName)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            if !SharedUtils.connectAndLoginSync(using: tinode, inBackground: false) {
                UiUtils.logoutAndRouteToLoginVC()
            } else {
                UiUtils.routeToMessageVC(forTopic: topicName)
            }
        }
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // Update token. Send to the app server.
        guard let token = fcmToken else { return }
        Cache.tinode.setDeviceToken(token: token)
    }
}

extension AppDelegate: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        print("PK token received %s", credentials.debugDescription)
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        print("PK must invalidate token")
    }

    // VoIP push notification recived.
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        print("PK push %s", payload.debugDescription)

        if type != .voIP {
            completion()
            return
        }

        // Cannot defer completion() because it's called from a closure.

        guard let data = payload.dictionaryPayload["data"] as? [String: Any], let topicName = data["topic"] as? String, let callState = data["webrtc"] as? String else {
            Cache.log.error("Missing payload data")
            completion()
            return
        }

        switch callState {
        case "started":
            guard let callerUID = data["xfrom"] as? String, !Cache.tinode.isMe(uid: callerUID), let seq = Int(data["seq"] as? String ?? ""), seq > 0 else {
                completion()
                return
            }
            // Report the call to CallKit, and let it display the call UI.
            Cache.callManager.displayIncomingCall(uuid: UUID(), onTopic: topicName, originatingFrom: callerUID, withSeqId: seq, completion: { err in
                // Tell PushKit that the notification is handled.
                completion()
            })
        case "accepted", "missed", "declined", "disconnected":
            // This should not happen: the server sends just the "started" push as voip.
            guard let origSeq = Int(data["replace"] as? String ?? ""), origSeq > 0 else { return }
            Cache.callManager.dismissIncomingCall(onTopic: topicName, withSeqId: origSeq)
            fallthrough
        default:
            completion()
            break
        }
    }
}
