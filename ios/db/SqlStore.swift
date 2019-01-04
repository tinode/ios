//
//  SqlStore.swift
//  msgr
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

class SqlStore : Storage {
    var myUid: String? {
        get {
            return self.dbh?.uid
        }
        set {
            self.dbh?.setUid(uid: newValue)
        }
    }
    
    var deviceToken: String?
    var dbh: BaseDb?
    
    init(dbh: BaseDb) {
        self.dbh = dbh
    }
    
    func logout() {
        self.dbh?.logout()
    }
    
    func setTimeAdjustment(adjustment: TimeInterval) {
        // todo
    }
    
    var isReady: Bool { get { return self.dbh?.isReady ?? false }}
    
    func topicGetAll(from tinode: Tinode?) -> [TopicProto]? {
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
    
    func topicAdd(topic: TopicProto) -> Int64 {
        if let st = topic.payload as? StoredTopic {
            return st.id ?? 0
        }
        return self.dbh?.topicDb?.insert(topic: topic) ?? 0
    }
    
    func topicUpdate(topic: TopicProto) -> Bool {
        return self.dbh?.topicDb?.update(topic: topic) ?? false
    }
    
    func topicDelete(topic: TopicProto) -> Bool {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else { return false }
        do {
            try dbh?.db?.transaction {
                // TODO:
                // self.dbh?.messageDb?.delete(st.id, from: 0, told: -1)
                // self.dbh?.subscriberDb?.deleteForTopic(st.id)
                self.dbh?.topicDb?.delete(recordId: topicId)
            }
            return true
        } catch {
            print("topicDelete failed: \(error)")
            return false
        }
    }
    
    func getCachedMessagesRange(topic: TopicProto) -> Storage.Range? {
        guard let st = topic.payload as? StoredTopic else { return nil }
        return (st.minLocalSeq!, st.maxLocalSeq!)
    }
    
    func setRead(topic: TopicProto, read: Int) -> Bool {
        guard let st = topic.payload as? StoredTopic,
            let topicId = st.id, topicId > 0 else { return false }
        return self.dbh?.topicDb?.updateRead(for: topicId, with: read) ?? false
    }
    
    func setRecv(topic: TopicProto, recv: Int) -> Bool {
        guard let st = topic.payload as? StoredTopic,
            let topicId = st.id, topicId > 0 else { return false }
        return self.dbh?.topicDb?.updateRecv(for: topicId, with: recv) ?? false
    }
    
    func subAdd(topic: TopicProto, sub: SubscriptionProto) -> Int64 {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else {
            return 0
        }
        return self.dbh?.subscriberDb?.insert(for: topicId, with: BaseDb.kStatusSynced, using: sub) ?? 0
    }
    
    func subUpdate(topic: TopicProto, sub: SubscriptionProto) -> Bool {
        guard let ss = sub.payload as? StoredSubscription, let subId = ss.id, subId > 0 else {
            return false
        }
        return self.dbh?.subscriberDb?.update(using: sub) ?? false
    }
    
    func subNew(topic: TopicProto, sub: SubscriptionProto) -> Int64 {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else {
            return 0
        }
        return self.dbh?.subscriberDb?.insert(for: topicId, with: BaseDb.kStatusQueued, using: sub) ?? 0
    }
    
    func subDelete(topic: TopicProto, sub: SubscriptionProto) -> Bool {
        guard let ss = sub.payload as? StoredSubscription, let subId = ss.id, subId > 0 else {
            return false
        }
        return self.dbh?.subscriberDb?.delete(recordId: subId) ?? false
    }
    
    func getSubscriptions(topic: TopicProto) -> [SubscriptionProto]? {
        guard let st = topic.payload as? StoredTopic, let topicId = st.id else {
            return nil
        }
        return self.dbh?.subscriberDb?.readAll(topicId: topicId)
    }
    
    func userGet(uid: String) -> UserProto? {
        return self.dbh?.userDb?.readOne(uid: uid)
    }
    
    func userAdd(user: UserProto) -> Int64 {
        return self.dbh?.userDb?.insert(user: user) ?? 0
    }
    
    func userUpdate(user: UserProto) -> Bool {
        return self.dbh?.userDb?.update(user: user) ?? false
    }
    
    func msgReceived(topic: TopicProto, sub: SubscriptionProto?, msg: MsgServerData?) -> Int64 {
        return 0
    }
    
    func msgSend(topic: TopicProto, data: Drafty) -> Int64 {
        return 0
    }
    
    func msgDraft(topic: TopicProto, data: Drafty) -> Int64 {
        return 0
    }
    
    func msgDraftUpdate(topic: TopicProto, dbMessageId: Int64, data: Drafty) -> Bool {
        return false
    }
    
    func msgReady(topic: TopicProto, dbMessageId: Int64, data: Drafty) -> Bool {
        return false
    }
    
    func msgDiscard(topic: TopicProto, dbMessageId: Int64) -> Bool {
        return false
    }
    
    func msgDelivered(topic: TopicProto, dbMessageId: Int64, timestamp: Date, seq: Int) -> Bool {
        return false
    }
    
    func msgMarkToDelete(topic: TopicProto, from idLo: Int, to idHi: Int, markAsHard: Bool) -> Bool {
        return false
    }
    
    func msgMarkToDelete(topic: TopicProto, list: [Int], markAsHard: Bool) -> Bool {
        return false
    }
    
    func msgDelete(topic: TopicProto, delete id: Int, deleteFrom idLo: Int, deleteTo idHi: Int) -> Bool {
        return false
    }
    
    func msgDelete(topic: TopicProto, delete id: Int, deleteAll list: [Int]?) -> Bool {
        return false
    }
    
    func msgRecvByRemote(sub: SubscriptionProto, recv: Int?) -> Bool {
        return false
    }
    
    func msgReadByRemote(sub: SubscriptionProto, read: Int?) -> Bool {
        return false
    }
    
    func getMessageById(topic: TopicProto, dbMessageId: Int64) -> Message? {
        return nil
    }
    
    func getQueuedMessages(topic: TopicProto) -> MessageIterator? {
        return nil
    }
}
