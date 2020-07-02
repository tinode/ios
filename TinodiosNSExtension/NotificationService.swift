//
//  NotificationService.swift
//  TinodiosNSExtension
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UserNotifications
import TinodeSDK
import TinodiosDB

@available(iOS 10, *)
class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    let log = TinodeSDK.Log(subsystem: BaseDb.kBundleId)

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        // New message notification (msg):
        // - P2P
        //   Title: <sender name> || 'Unknown'
        //   Body: <message content> || 'New message'
        // - GRP
        //   Title: <topic name> || 'Unknown'
        //   Body: <sender name>: <message content> || 'New message'
        //
        // New subscription notification (sub):
        // - P2P
        //   Title: 'New chat'
        //   Body: <sender name> || 'Unknown'
        // - GRP
        //   Title: 'New chat'
        //   Body: <group name> || 'Unknown'

        if let bestAttemptContent = bestAttemptContent {
            defer { self.contentHandler!(bestAttemptContent) }

            let store = BaseDb.getInstance().sqlStore!

            let userInfo = bestAttemptContent.userInfo
            guard let topic = userInfo["topic"] as? String, !topic.isEmpty,
                let xfrom = userInfo["xfrom"] as? String, !xfrom.isEmpty else { return }
            let action = userInfo["what"] as? String ?? "msg"
            var user = store.userGet(uid: xfrom) as? DefaultUser
            if user == nil {
                // If we don't have the user info, fetch it from the server.
                let tinode = SharedUtils.createTinode()
                self.log.info("Fetching desc from server for user %@.", xfrom)
                if SharedUtils.fetchDesc(using: tinode, for: xfrom) == .newData {
                    // Server replies asynchronously. Give the thread 1 second to receive and persist the data.
                    Thread.sleep(forTimeInterval: 1)
                    user = store.userGet(uid: xfrom) as? DefaultUser
                } else {
                    self.log.info("No new desc data fetched for %@.", xfrom)
                }
                tinode.disconnect()
            }

            let senderName = user?.pub?.fn ?? "Unknown"
            switch Tinode.topicTypeByName(name: topic) {
            case .p2p:
                if action == "msg" {
                    bestAttemptContent.title = senderName
                } else if action == "sub" {
                    bestAttemptContent.title = "New chat"
                    bestAttemptContent.body = senderName
                }
                break
            case .grp:
                let topic = store.topicGet(from: nil, withName: topic) as? DefaultComTopic
                if action == "msg" {
                    bestAttemptContent.title = topic?.pub?.fn ?? "Unknown"
                    bestAttemptContent.body = senderName + ": " + bestAttemptContent.body
                } else if action == "sub" {
                    bestAttemptContent.title = "New chat"
                    bestAttemptContent.body = topic?.pub?.fn ?? "Unknown"
                }
                break
            default:
                return
            }
        } else {
            self.contentHandler!(request.content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // 30 seconds.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}
