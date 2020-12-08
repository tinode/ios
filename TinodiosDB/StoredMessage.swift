//
//  StoredMessage.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

public class StoredMessage : MsgServerData, Message {
    public var msgId: Int64 = 0

    public var seqId: Int { return seq ?? 0 }

    var topicId: Int64? = nil
    var userId: Int64? = nil

    var dbStatus: BaseDb.Status? = nil
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

    /// Cached representation of message content as attributed string.
    public var cachedContent: NSAttributedString?

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
}
