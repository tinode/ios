//
//  SqlStore.swift
//  msgr
//
//  Copyright © 2019-2023 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

enum SqlStoreError: Error {
    case dbError(String)
}

public class SqlStore: Storage {
    public var myUid: String? {
        get {
            return self.dbh?.uid
        }
        set {
            self.dbh?.setUid(uid: newValue, credMethods: nil)
        }
    }

    public var deviceToken: String? {
        get { self.dbh?.accountDb?.getDeviceToken() }
        set { self.dbh?.accountDb?.saveDeviceToken(token: newValue) }
    }
    var dbh: BaseDb?
    var myId: Int64 = -1

    init(dbh: BaseDb) {
        self.dbh = dbh
    }

    public func logout() {
        self.dbh?.logout()
    }

    public func deleteAccount(_ uid: String) {
        if !(self.dbh?.deleteUid(uid) ?? true) {
            BaseDb.log.info("Account deletion did not succeed. Uid [%@]", uid)
        }
    }

    public func setMyUid(uid: String, credMethods: [String]?) {
        self.dbh?.setUid(uid: uid, credMethods: credMethods)
    }

    public func setTimeAdjustment(adjustment: TimeInterval) {
        self.timeAdjustment = adjustment
    }
    var timeAdjustment: TimeInterval = TimeInterval(0)
    public var isReady: Bool { get { return self.dbh?.isReady ?? false }}

    public func topicGetAll(from tinode: Tinode?) -> [TopicProto]? {
        guard let tdb = self.dbh?.topicDb, let rows = tdb.query() else {
            return nil
        }
        var results: [TopicProto] = []
        for r in rows {
            if let t = tdb.readOne(for: tinode, row: r) {
                results.append(t)
            }
        }
        return results
    }

    public func topicGet(from tinode: Tinode?, withName name: String?) -> TopicProto? {
        guard let tdb = self.dbh?.topicDb else { return nil }
        return tdb.readOne(for: tinode, withName: name)
    }

    public func topicAdd(topic: TopicProto) -> Int64 {
        if let st = topic.payload as? StoredTopic {
            return st.id ?? 0
        }
        return self.dbh?.topicDb?.insert(topic: topic) ?? 0
    }

    public func topicUpdate(topic: TopicProto) -> Bool {
        return self.dbh?.topicDb?.update(topic: topic) ?? false
    }

    public func topicDelete(topic: TopicProto, hard: Bool) -> Bool {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else { return false }
        let savepointName = "SqlStore.topicDelete"
        do {
            if hard {
                try dbh?.db?.savepoint(savepointName) {
                    self.dbh?.messageDb?.deleteAll(forTopic: topicId)
                    self.dbh?.subscriberDb?.deleteForTopic(topicId: topicId)
                    self.dbh?.topicDb?.delete(recordId: topicId)
                }
            } else {
                self.dbh?.topicDb?.markDeleted(recordId: topicId)
            }
            return true
        } catch {
            dbh?.db?.releaseSavepoint(withName: savepointName)
            BaseDb.log.error("SqlStore - topicDelete operation failed: topicId = %lld, error = %@", topicId, error.localizedDescription)
            return false
        }
    }

    public func msgIsCached(topic: TopicProto, ranges: [MsgRange]) -> [MsgRange] {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else { return [] }
        return self.dbh?.messageDb?.getCachedRanges(topicId: topicId, ranges: ranges) ?? []
    }

    public func getCachedMessagesRange(topic: TopicProto) -> MsgRange? {
        guard let st = topic.payload as? StoredTopic else { return nil }
        return MsgRange(low: st.minLocalSeq ?? 0, hi: (st.maxLocalSeq ?? 0) + 1)
    }

    public func getMissingRanges(topic: TopicProto, startFrom: Int, pageSize: Int, newer: Bool) -> [MsgRange] {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else { return [] }
        return self.dbh?.messageDb?.getMissingRanges(topicId: topicId, startFrom: startFrom, pageSize: pageSize, newer: newer) ?? []
    }

    public func setRead(topic: TopicProto, read: Int) -> Bool {
        guard let st = topic.payload as? StoredTopic,
            let topicId = st.id, topicId > 0 else { return false }
        return self.dbh?.topicDb?.updateRead(for: topicId, with: read) ?? false
    }

    public func setRecv(topic: TopicProto, recv: Int) -> Bool {
        guard let st = topic.payload as? StoredTopic,
            let topicId = st.id, topicId > 0 else { return false }
        return self.dbh?.topicDb?.updateRecv(for: topicId, with: recv) ?? false
    }

    public func subAdd(topic: TopicProto, sub: SubscriptionProto) -> Int64 {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else {
            return 0
        }
        return self.dbh?.subscriberDb?.insert(for: topicId, with: .synced, using: sub) ?? 0
    }

    public func subUpdate(topic: TopicProto, sub: SubscriptionProto) -> Bool {
        guard let ss = sub.payload as? StoredSubscription, let subId = ss.id, subId > 0 else {
            return false
        }
        return self.dbh?.subscriberDb?.update(using: sub) ?? false
    }

    public func subNew(topic: TopicProto, sub: SubscriptionProto) -> Int64 {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else {
            return 0
        }
        return self.dbh?.subscriberDb?.insert(for: topicId, with: .queued, using: sub) ?? 0
    }

    public func subDelete(topic: TopicProto, sub: SubscriptionProto) -> Bool {
        guard let ss = sub.payload as? StoredSubscription, let subId = ss.id, subId > 0 else {
            return false
        }
        return self.dbh?.subscriberDb?.delete(recordId: subId) ?? false
    }

    public func getSubscriptions(topic: TopicProto) -> [SubscriptionProto]? {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else {
            return nil
        }
        return self.dbh?.subscriberDb?.readAll(topicId: topicId)
    }

    public func userGet(uid: String) -> UserProto? {
        return self.dbh?.userDb?.readOne(uid: uid)
    }

    public func userAdd(user: UserProto) -> Int64 {
        return self.dbh?.userDb?.insert(user: user) ?? 0
    }

    public func userUpdate(user: UserProto) -> Bool {
        return self.dbh?.userDb?.update(user: user) ?? false
    }

    public func msgReceived(topic: TopicProto, sub: SubscriptionProto?, msg: MsgServerData?) -> Message? {
        guard let msg = msg else { return nil }

        var topicId: Int64 = -1
        var userId: Int64 = -1
        if let ss = sub?.payload as? StoredSubscription {
            topicId = ss.topicId ?? -1
            userId = ss.userId ?? -1
        } else if let st = topic.payload as? StoredTopic {
            // Message from a new/unknown subscriber.

            topicId = st.id ?? -1
            userId = self.dbh?.userDb?.getId(for: msg.from) ?? -1
            if userId < 0 {
                // Create a placeholder user to satisfy foreign key constraint.
                if sub != nil {
                    userId = self.dbh?.userDb?.insert(sub: sub) ?? -1
                } else {
                    userId = self.dbh?.userDb?.insert(uid: msg.from, updated: msg.ts, serializedPub: nil) ?? -1
                }
            }
        }

        guard topicId >= 0 && userId >= 0 else {
            BaseDb.log.error("SqlStore - msgReceived: either user or topic not available, quitting.")
            return nil
        }
        let sm = StoredMessage(from: msg)
        sm.topicId = topicId
        sm.userId = userId
        sm.dbStatus = .synced
        let savepointName = "SqlStore.msgReceived"
        do {
            try dbh?.db?.savepoint(savepointName) {
                sm.msgId = self.dbh?.messageDb?.insert(topic: topic, msg: sm) ?? -1
                if sm.msgId <= 0 || !(self.dbh?.topicDb?.msgReceived(topic: topic, ts: sm.ts ?? Date(), seq: sm.seqId) ?? false) {
                    throw SqlStoreError.dbError("Could not handle received message: msgId = \(sm.msgId), topicId = \(topicId), userId = \(userId)")
                }
            }
            return sm
        } catch {
            dbh?.db?.releaseSavepoint(withName: savepointName)
            BaseDb.log.error("SqlStore - msgReceived operation failed: %@", error.localizedDescription)
            return nil
        }
    }
    private func insertMessage(topic: TopicProto, data: Drafty, head: [String: JSONValue]?, initialStatus: BaseDb.Status) -> Message? {
        let msg = StoredMessage()
        msg.topic = topic.name
        msg.from = myUid
        msg.ts = Date() + timeAdjustment
        msg.seq = 0
        msg.dbStatus = initialStatus
        msg.content = data
        msg.head = head
        msg.topicId = (topic.payload as? StoredTopic)?.id ?? -1
        if myId < 0 {
            myId = self.dbh?.userDb?.getId(for: msg.from) ?? -1
        }
        msg.userId = myId
        let id = self.dbh?.messageDb?.insert(topic: topic, msg: msg) ?? -1
        return id > 0 ? msg : nil
    }

    public func msgSend(topic: TopicProto, data: Drafty, head: [String: JSONValue]?) -> Message? {
        return self.insertMessage(topic: topic, data: data, head: head, initialStatus: .undefined)
    }

    public func msgDraft(topic: TopicProto, data: Drafty, head: [String: JSONValue]?) -> Message? {
        return self.insertMessage(topic: topic, data: data, head: head, initialStatus: .draft)
    }

    public func msgDraftUpdate(topic: TopicProto, dbMessageId: Int64, data: Drafty) -> Bool {
        return self.dbh?.messageDb?.updateStatusAndContent(
            msgId: dbMessageId,
            status: .undefined,
            content: data) ?? false
    }

    public func msgReady(topic: TopicProto, dbMessageId: Int64, data: Drafty) -> Bool {
        return self.dbh?.messageDb?.updateStatusAndContent(
            msgId: dbMessageId,
            status: .queued,
            content: data) ?? false
    }

    public func msgSyncing(topic: TopicProto, dbMessageId: Int64, sync: Bool) -> Bool {
        return self.dbh?.messageDb?.updateStatusAndContent(
            msgId: dbMessageId,
            status: sync ? .sending : .queued,
            content: nil) ?? false
    }

    public func msgFailed(topic: TopicProto, dbMessageId: Int64) -> Bool {
        return self.dbh?.messageDb?.updateStatusAndContent(
            msgId: dbMessageId,
            status: .failed,
            content: nil) ?? false
    }

    public func msgPruneFailed(topic: TopicProto) -> Bool {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else { return false }
        return self.dbh?.messageDb?.deleteFailed(forTopic: topicId) ?? false
    }

    public func msgDiscard(topic: TopicProto, dbMessageId: Int64) -> Bool {
        return self.dbh?.messageDb?.delete(msgId: dbMessageId) ?? false
    }

    public func msgDiscard(topic: TopicProto, seqId: Int) -> Bool {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else { return false }
        return self.dbh?.messageDb?.delete(inTopic: topicId, seqId: seqId) ?? false
    }

    public func msgDelivered(topic: TopicProto, dbMessageId: Int64, timestamp: Date, seq: Int) -> Bool {
        let savepointName = "SqlStore.msgDelivered"
        do {
            try dbh?.db?.savepoint(savepointName) {
                let messageDbSuccessful = self.dbh?.messageDb?.delivered(msgId: dbMessageId, ts: timestamp, seq: seq) ?? false
                let topicDbSuccessful = self.dbh?.topicDb?.msgReceived(topic: topic, ts: timestamp, seq: seq) ?? false
                if !(messageDbSuccessful && topicDbSuccessful) {
                    throw SqlStoreError.dbError("messageDb = \(messageDbSuccessful), topicDb = \(topicDbSuccessful)")
                }
            }
            return true
        } catch {
            dbh?.db?.releaseSavepoint(withName: savepointName)
            BaseDb.log.error("SqlStore - msgDelivered operation failed %@", error.localizedDescription)
            return false
        }
    }

    public func msgMarkToDelete(topic: TopicProto, from idLo: Int, to idHi: Int, markAsHard: Bool) -> Bool {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else { return false }
        return self.dbh?.messageDb?.deleteOrMarkDeleted(topicId: topicId, delId: nil, from: idLo, to: idHi, hard: markAsHard) ?? false
    }

    public func msgMarkToDelete(topic: TopicProto, ranges: [MsgRange]?, markAsHard: Bool) -> Bool {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id,
            let ranges = ranges, !ranges.isEmpty else { return false }
        return self.dbh?.messageDb?.deleteOrMarkDeleted(topicId: topicId, delId: nil, inRanges: ranges, hard: markAsHard) ?? false
    }

    public func msgDelete(topic: TopicProto, delete delId: Int, deleteFrom idLo: Int, deleteTo idHi: Int) -> Bool {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else { return false }
        let idHi = idHi <= 0 ? (st.maxLocalSeq ?? 0) + 1 : idHi
        var success = false
        let savepointName = "SqlStore.msgDelete-bounds"
        do {
            try dbh?.db?.savepoint(savepointName) {
                success = (dbh?.topicDb?.msgDeleted(topic: topic, delId: delId, from: idLo, to: idHi) ?? false) &&
                    (dbh?.messageDb?.delete(topicId: topicId, deleteId: delId, from: idLo, to: idHi) ?? false)
            }
        } catch {
            dbh?.db?.releaseSavepoint(withName: savepointName)
            BaseDb.log.error("SqlStore - msgDelete operation failed %@", error.localizedDescription)
        }
        return success
    }

    public func msgDelete(topic: TopicProto, delete delId: Int, deleteAllIn ranges: [MsgRange]?) -> Bool {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id,
            let ranges = ranges, !ranges.isEmpty else { return false }
        let collapsedRanges = MsgRange.collapse(ranges)
        let enclosing = MsgRange.enclosing(for: collapsedRanges)
        var success = false
        let savepointName = "SqlStore.msgDelete-ranges"
        do {
            try dbh?.db?.savepoint(savepointName) {
                success = (dbh?.topicDb?.msgDeleted(topic: topic, delId: delId, from: enclosing!.lower, to: enclosing!.upper) ?? false) &&
                    (dbh?.messageDb?.deleteOrMarkDeleted(topicId: topicId, delId: delId, inRanges: collapsedRanges, hard: false) ?? false)
            }
        } catch {
            // Explicitly releasing savepoint since ROLLBACK TO (SQLite.swift behavior) won't release the savepoint transaction.
            dbh?.db?.releaseSavepoint(withName: savepointName)
            BaseDb.log.error("SqlStore - msgDelete operation failed %@", error.localizedDescription)
        }
        return success
    }

    public func msgRecvByRemote(sub: SubscriptionProto, recv: Int?) -> Bool {
        guard let ss = sub.payload as? StoredSubscription, let sid = ss.id, sid > 0, let recv = recv else {
            return false
        }
        return BaseDb.sharedInstance.subscriberDb?.updateRecv(for: sid, with: recv) ?? false
    }

    public func msgReadByRemote(sub: SubscriptionProto, read: Int?) -> Bool {
        guard let ss = sub.payload as? StoredSubscription, let sid = ss.id, sid > 0, let read = read else {
            return false
        }
        return BaseDb.sharedInstance.subscriberDb?.updateRead(for: sid, with: read) ?? false
    }

    private func messageById(dbId: Int64, previewLen: Int = -1) -> Message? {
        return BaseDb.sharedInstance.messageDb?.query(msgId: dbId, previewLen: previewLen)
    }

    public func getMessageById(dbMessageId: Int64) -> Message? {
        return messageById(dbId: dbMessageId)
    }

    public func getMessagePreviewById(dbMessageId: Int64) -> Message? {
        return messageById(dbId: dbMessageId, previewLen: MessageDb.kMessagePreviewLength)
    }

    public func getQueuedMessages(topic: TopicProto) -> [Message]? {
        guard let st = topic.payload as? StoredTopic else { return nil }
        guard let id = st.id, id > 0 else { return nil }
        return BaseDb.sharedInstance.messageDb?.queryUnsent(topicId: id)
    }

    public func getQueuedMessageDeletes(topic: TopicProto, hard: Bool) -> [MsgRange]? {
        guard let st = topic.payload as? StoredTopic, let id = st.id, id > 0 else { return nil }
        return BaseDb.sharedInstance.messageDb?.queryDeleted(topicId: id, hard: hard)
    }

    public func getLatestMessagePreviews() -> [Message]? {
        return BaseDb.sharedInstance.messageDb?.queryLatest()
    }

    /// Return the message page starting at the `from`.
    public func getMessagePage(topic: TopicProto, from: Int, limit: Int, forward: Bool) -> [Message]? {
        guard let st = topic.payload as? StoredTopic, let id = st.id, id > 0 else { return nil }
        return BaseDb.sharedInstance.messageDb?.query(topicId: id, from: from, limit: limit, forward: forward)
    }

    public func getMessage(fromTopic topic: TopicProto, byEffectiveSeqId seqId: Int) -> Message? {
        guard let st = topic.payload as? StoredTopic, let id = st.id, id > 0 else { return nil }
        return BaseDb.sharedInstance.messageDb?.getMessage(fromTopic: id, byEffectiveSeq: seqId)
    }

    public func getAllMsgVersions(fromTopic topic: TopicProto, forSeq seqId: Int, limit: Int?) -> [Int]? {
        guard let st = topic.payload as? StoredTopic, let id = st.id, id > 0 else { return nil }
        return BaseDb.sharedInstance.messageDb?.getAllVersions(fromTopic: id, forSeq: seqId, limit: limit)
    }
}
