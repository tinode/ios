//
//  StoredMessage.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

public class StoredMessage: MsgServerData, Message {
    public var msgId: Int64 = 0

    public var seqId: Int { return seq ?? 0 }

    var topicId: Int64?
    var userId: Int64?

    var dbStatus: BaseDb.Status?
    public var status: Int? {
        return dbStatus?.rawValue
    }

    public var isDraft: Bool { get { return dbStatus == .draft } }
    public var isReady: Bool { get { return dbStatus == .queued } }
    public var isDeleted: Bool {
        return dbStatus == .deletedHard || dbStatus == .deletedSoft || dbStatus == .deletedSynced
    }
    public func isDeleted(hard: Bool) -> Bool {
        return hard ?
            dbStatus == .deletedHard :
            dbStatus == .deletedSoft
    }
    public var isSynced: Bool { return dbStatus == .synced }

    /// Message has not been delivered to the server yet.
    public var isPending: Bool { return dbStatus == nil || dbStatus! <= .sending }

    /// True if message was forwarded from another topic.
    public var isForwarded: Bool {
        return !(head?["forwarded"]?.asString()?.isEmpty ?? true)
    }

    /// True if message has been edited.
    public var isEdited: Bool {
        return head?["replace"] != nil && head?["webrtc"] == nil
    }

    /// True if the acount owner is the author of the message.
    public var isMine: Bool {
        return BaseDb.sharedInstance.isMe(uid: self.from)
    }

    /// Cached representation of message content as attributed string.
    public var cachedContent: NSAttributedString?

    /// Cached representation of message preview as attributed string.
    public var cachedPreview: NSAttributedString?

    // MARK: initializers

    public override init() { super.init() }

    convenience init(from m: MsgServerData) {
        self.init()
        self.topic = m.topic
        self.head = m.head
        self.from = m.from
        self.ts = m.ts
        self.seq = m.seq
        self.content = m.content
    }

    convenience init(from m: MsgServerData, status: BaseDb.Status) {
        self.init(from: m)
        self.dbStatus = status
    }

    required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }

    // Makes a shallow copy of self.
    public func copyOf() -> StoredMessage {
        let cp = StoredMessage(from: self)
        cp.msgId = self.msgId
        cp.topicId = self.topicId
        cp.userId = self.userId
        cp.dbStatus = self.dbStatus
        cp.cachedContent = self.cachedContent
        cp.cachedPreview = self.cachedPreview
        return cp
    }
}
