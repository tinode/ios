//
//  SqlStore.swift
//  msgr
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

enum SqlStoreError: Error {
    case dbError(String)
}

public class SqlStore : Storage {
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

    public func topicDelete(topic: TopicProto) -> Bool {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else { return false }
        do {
            try dbh?.db?.savepoint("SqlStore.topicDelete") {
                self.dbh?.messageDb?.delete(topicId: topicId, from: 0, to: nil)
                self.dbh?.subscriberDb?.deleteForTopic(topicId: topicId)
                self.dbh?.topicDb?.delete(recordId: topicId)
            }
            return true
        } catch {
            BaseDb.log.error("SqlStore - topicDelete operation failed: topicId = %lld, error = %@", topicId, error.localizedDescription)
            return false
        }
    }

    public func getCachedMessagesRange(topic: TopicProto) -> Storage.Range? {
        guard let st = topic.payload as? StoredTopic else { return nil }
        return (st.minLocalSeq ?? 0, st.maxLocalSeq ?? 0)
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
        return self.dbh?.subscriberDb?.insert(for: topicId, with: BaseDb.kStatusSynced, using: sub) ?? 0
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
        return self.dbh?.subscriberDb?.insert(for: topicId, with: BaseDb.kStatusQueued, using: sub) ?? 0
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

    public func msgReceived(topic: TopicProto, sub: SubscriptionProto?, msg: MsgServerData?) -> Int64 {
        guard let msg = msg else { return -1 }

        var topicId: Int64 = -1
        var userId: Int64 = -1
        if let ss = sub?.payload as? StoredSubscription {
            topicId = ss.topicId ?? -1
            userId = ss.userId ?? -1
        } else {
            let st = topic.payload as! StoredTopic
            topicId = st.id ?? -1
            userId = self.dbh?.userDb?.getId(for: msg.from) ?? -1
        }
        guard topicId >= 0 && userId >= 0 else {
            return -1
        }
        let sm = StoredMessage(from: msg)
        sm.topicId = topicId
        sm.userId = userId
        do {
            try dbh?.db?.savepoint("SqlStore.msgReceived") {
                sm.msgId = self.dbh?.messageDb?.insert(topic: topic, msg: sm) ?? -1
                if sm.msgId <= 0 || !(self.dbh?.topicDb?.msgReceived(topic: topic, ts: sm.ts ?? Date(), seq: sm.seqId) ?? false) {
                    throw SqlStoreError.dbError("Could not handle received message: msgId = \(sm.msgId), topicId = \(topicId), userId = \(userId)")
                }
            }
            return sm.msgId
        } catch {
            BaseDb.log.error("SqlStore - msgReceived operation failed: %@", error.localizedDescription)
            return -1
        }
    }
    private func insertMessage(topic: TopicProto, data: Drafty, head: [String: JSONValue]?, initialStatus: Int) -> Int64 {
        let msg = StoredMessage()
        msg.topic = topic.name
        msg.from = myUid
        msg.ts = Date() + timeAdjustment
        msg.seq = 0
        msg.status = initialStatus
        msg.content = data
        msg.head = head
        msg.topicId = (topic.payload as? StoredTopic)?.id ?? -1
        if myId < 0 {
            myId = self.dbh?.userDb?.getId(for: msg.from) ?? -1
        }
        msg.userId = myId
        return self.dbh?.messageDb?.insert(topic: topic, msg: msg) ?? -1
    }

    public func msgSend(topic: TopicProto, data: Drafty, head: [String: JSONValue]?) -> Int64 {
        return self.insertMessage(topic: topic, data: data, head: head, initialStatus: BaseDb.kStatusUndefined)
    }

    public func msgDraft(topic: TopicProto, data: Drafty, head: [String: JSONValue]?) -> Int64 {
        return self.insertMessage(topic: topic, data: data, head: head, initialStatus: BaseDb.kStatusDraft)
    }

    public func msgDraftUpdate(topic: TopicProto, dbMessageId: Int64, data: Drafty) -> Bool {
        return self.dbh?.messageDb?.updateStatusAndContent(
            msgId: dbMessageId,
            status: BaseDb.kStatusUndefined,
            content: data) ?? false
    }

    public func msgReady(topic: TopicProto, dbMessageId: Int64, data: Drafty) -> Bool {
        return self.dbh?.messageDb?.updateStatusAndContent(
            msgId: dbMessageId,
            status: BaseDb.kStatusQueued,
            content: data) ?? false
    }

    public func msgSyncing(topic: TopicProto, dbMessageId: Int64, sync: Bool) -> Bool {
        return self.dbh?.messageDb?.updateStatusAndContent(
            msgId: dbMessageId,
            status: sync ? BaseDb.kStatusSending : BaseDb.kStatusQueued,
            content: nil) ?? false
    }

    public func msgDiscard(topic: TopicProto, dbMessageId: Int64) -> Bool {
        return self.dbh?.messageDb?.delete(msgId: dbMessageId) ?? false
    }

    public func msgDelivered(topic: TopicProto, dbMessageId: Int64, timestamp: Date, seq: Int) -> Bool {
        do {
            try dbh?.db?.savepoint("SqlStore.msgDelivered") {
                let messageDbSuccessful = self.dbh?.messageDb?.delivered(msgId: dbMessageId, ts: timestamp, seq: seq) ?? false
                let topicDbSuccessful = self.dbh?.topicDb?.msgReceived(topic: topic, ts: timestamp, seq: seq) ?? false
                if !(messageDbSuccessful && topicDbSuccessful) {
                    throw SqlStoreError.dbError("messageDb = \(messageDbSuccessful), topicDb = \(topicDbSuccessful)")
                }
            }
            return true
        } catch {
            BaseDb.log.error("SqlStore - msgDelivered operation failed %@", error.localizedDescription)
            return false
        }
    }

    public func msgMarkToDelete(topic: TopicProto, from idLo: Int, to idHi: Int, markAsHard: Bool) -> Bool {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else { return false }
        return self.dbh?.messageDb?.markDeleted(topicId: topicId, from: idLo, to: idHi, hard: markAsHard) ?? false
    }

    public func msgMarkToDelete(topic: TopicProto, list: [Int], markAsHard: Bool) -> Bool {
        return false
    }

    public func msgDelete(topic: TopicProto, delete id: Int, deleteFrom idLo: Int, deleteTo idHi: Int) -> Bool {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else { return false }
        do {
            var result = false
            try dbh?.db?.savepoint("SqlStore.msgDelete") {
                result = (dbh?.topicDb?.msgDeleted(topic: topic, delId: id) ?? false) &&
                    (dbh?.messageDb?.delete(topicId: topicId, from: idLo, to: idHi) ?? false)
            }
            return result
        } catch {
            BaseDb.log.error("SqlStore - msgDelete operation failed %@", error.localizedDescription)
            return false
        }
    }

    public func msgDelete(topic: TopicProto, delete id: Int, deleteAll list: [Int]?) -> Bool {
        return false
    }

    public func msgRecvByRemote(sub: SubscriptionProto, recv: Int?) -> Bool {
        guard let ss = sub.payload as? StoredSubscription, let sid = ss.id, sid > 0, let recv = recv else {
            return false
        }
        return BaseDb.getInstance().subscriberDb?.updateRecv(for: sid, with: recv) ?? false
    }

    public func msgReadByRemote(sub: SubscriptionProto, read: Int?) -> Bool {
        guard let ss = sub.payload as? StoredSubscription, let sid = ss.id, sid > 0, let read = read else {
            return false
        }
        return BaseDb.getInstance().subscriberDb?.updateRead(for: sid, with: read) ?? false
    }

    public func getMessageById(topic: TopicProto, dbMessageId: Int64) -> Message? {
        return BaseDb.getInstance().messageDb?.query(msgId: dbMessageId)
    }

    public func getQueuedMessages(topic: TopicProto) -> [Message]? {
        guard let st = topic.payload as? StoredTopic else { return nil }
        guard let id = st.id, id > 0 else { return nil }
        return BaseDb.getInstance().messageDb?.queryUnsent(topicId: id)
    }

    public func getQueuedMessageDeletes(topic: TopicProto, hard: Bool) -> [Int]? {
        guard let st = topic.payload as? StoredTopic else { return nil }
        guard let id = st.id, id > 0 else { return nil }
        return BaseDb.getInstance().messageDb?.queryDeleted(topicId: id, hard: hard)
    }
}
