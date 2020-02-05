//
//  NotificationService.swift
//  TinodiosNSExtension
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UserNotifications
import TinodiosDB
import TinodeSDK

@available(iOS 10, *)
class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

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
            // TODO: handle silent pushes instead of ignoring them.
            let silent = userInfo["silent"] as? String
            if silent == "true" {
                return
            }
            guard let topic = userInfo["topic"] as? String, !topic.isEmpty,
                let xfrom = userInfo["xfrom"] as? String, !xfrom.isEmpty else { return }
            let action = userInfo["what"] as? String ?? "msg"
            let user = store.userGet(uid: xfrom) as? DefaultUser
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
