//
//  SubscriberDb.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import SQLite

class StoredSubscription: Payload  {
    let id: Int64? = nil
    let topicId: Int64? = nil
    let userId: Int64? = nil
    let status: Int? = nil
    /*
    public static long getId(Subscription sub) {
        StoredSubscription ss = (StoredSubscription) sub.getLocal();
        return ss == null ? -1 : ss.id;
    }
    */
}

class SubscriberDb {
    private static let kTableName = "subscriptions"
    private let db: SQLite.Connection
    
    private var table: Table? = nil
    
    private let id: Expression<Int64>
    private let topicId: Expression<Int64?>
    private let userId: Expression<Int64?>
    private let status: Expression<Int?>
    private let mode: Expression<String?>
    private let updated: Expression<Date?>
    //private let deleted:
    private let read: Expression<Int?>
    private let recv: Expression<Int?>
    private let clear: Expression<Int?>
    private let lastSeen: Expression<Date?>
    private let userAgent: Expression<String?>

    init(_ database: SQLite.Connection) {
        self.db = database
        self.id = Expression<Int64>("id")
        self.topicId = Expression<Int64?>("topic_id")
        self.userId = Expression<Int64?>("user_id")
        self.status = Expression<Int?>("status")
        self.mode = Expression<String?>("mode")
        self.updated = Expression<Date?>("updated")
        //self.deleted =
        self.read = Expression<Int?>("read")
        self.recv = Expression<Int?>("recv")
        self.clear = Expression<Int?>("clear")
        self.lastSeen = Expression<Date?>("last_seen")
        self.userAgent = Expression<String?>("user_agent")
    }
    func destroyTable() {
        try! self.db.run(self.table!.dropIndex(topicId))
        try! self.db.run(self.table!.drop(ifExists: true))
    }
    func createTable() {
        self.table = Table(SubscriberDb.kTableName)
        // Must succeed.
        try! self.db.run(self.table!.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(topicId)
            t.column(userId)
            t.column(status)
            t.column(mode)
            t.column(updated)
            //self.deleted =
            t.column(read)
            t.column(recv)
            t.column(clear)
            t.column(lastSeen)
            t.column(userAgent)

        })
        try! self.db.run(self.table!.createIndex(topicId, ifNotExists: true))
    }
    func insert(for topicId: Int64, with status: Int, using sub: SubscriptionProto) -> Int64 {
        /*
        let lastUsed = Date()
        do {
            try self.db.transaction {
                
            }
            let tp = topic.topicType
            let tpv = tp.rawValue
            //let pub = topic.
            let rowid = try db.run(
                self.table!.insert(
                    //email <- "alice@mac.com"
                    //accountId <- ,
                    status <- topic.isNew ? BaseDb.kStatusQueued : BaseDb.kStatusSynced,
                    self.topic <- topic.name,
                    type <- tpv,
                    visible <- TopicType.grp == tp || TopicType.p2p == tp ? 1 : 0,
                    created <- lastUsed,
                    updated <- topic.updated,
                    
                    read <- topic.read,
                    recv <- topic.recv,
                    seq <- topic.seq,
                    clear <- topic.clear,
                    maxDel <- topic.maxDel,
                    
                    accessMode <- topic.accessMode?.serialize(),
                    defacs <- topic.defacs?.serialize(),
                    self.lastUsed <- lastUsed,
                    minLocalSeq <- 0,
                    maxLocalSeq <- 0,
                    nextUnsentSeq <- TopicDb.kUnsentIdStart,
                    
                    tags <- topic.tags?.joined(separator: ","),
                    pub <- topic.serializePub(),
                    priv <- topic.serializePriv()
            ))
            if rowid > 0 {
                let st = StoredTopic(id: rowid, lastUsed: lastUsed, minLocalSeq: nil, maxLocalSeq: nil, status: nil, nextUnsentId: TopicDb.kUnsentIdStart)
                topic.payload = st
            }
            print("inserted id: \(rowid)")
            return rowid
        } catch {
            print("insertion failed: \(error)")
            return -1
        }
        */
        return -1
    }
}
