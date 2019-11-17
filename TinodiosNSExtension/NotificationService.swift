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

        if let bestAttemptContent = bestAttemptContent {
            defer { self.contentHandler!(bestAttemptContent) }

            let store = BaseDb.getInstance().sqlStore!

            let userInfo = bestAttemptContent.userInfo
            guard let topic = userInfo["topic"] as? String, !topic.isEmpty,
                let xfrom = userInfo["xfrom"] as? String, !xfrom.isEmpty else { return }

            guard let user = store.userGet(uid: xfrom) as? DefaultUser else { return }
            let senderName = user.pub?.fn ?? "Unknown"
            switch Tinode.topicTypeByName(name: topic) {
            case .p2p:
                bestAttemptContent.title = senderName
                break
            case .grp:
                guard let topic = store.topicGet(from: nil, withName: topic) as? DefaultComTopic else { return }
                bestAttemptContent.title = topic.pub?.fn ?? "Unknown"
                bestAttemptContent.body = senderName + ": " + bestAttemptContent.body
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
