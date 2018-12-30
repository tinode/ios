//
//  TopicDb.swift
//  msgr
//
//  Copyright © 2018 msgr. All rights reserved.
//

import Foundation
import SQLite

public struct StoredTopic: Payload {
    var id: Int64? = nil
    var lastUsed: Date? = nil
    var minLocalSeq: Int? = nil
    var maxLocalSeq: Int? = nil
    var status: Int? = nil
    var nextUnsentId: Int? = nil
}

public class TopicDb {
    private static let kTableName = "topics"
    private static let kUnsentIdStart = 2000000000
    private let db: SQLite.Connection
    
    private var table: Table? = nil

    private let id: Expression<Int64>
    private let accountId: Expression<Int64?>
    private let status: Expression<Int?>
    private let topic: Expression<String?>
    private let type: Expression<Int?>
    private let visible: Expression<Int64?>
    private let created: Expression<Date?>
    private let updated: Expression<Date?>
    private let read: Expression<Int?>
    private let recv: Expression<Int?>
    private let seq: Expression<Int?>
    private let clear: Expression<Int?>
    private let maxDel: Expression<Int?>
    private let accessMode: Expression<String?>
    private let defacs: Expression<String?>
    private let lastUsed: Expression<Date?>
    private let minLocalSeq: Expression<Int?>
    private let maxLocalSeq: Expression<Int?>
    private let nextUnsentSeq: Expression<Int?>
    private let tags: Expression<String?>
    private let pub: Expression<String?>
    private let priv: Expression<String?>
    
    init(_ database: SQLite.Connection) {
        self.db = database
        self.id = Expression<Int64>("id")
        self.accountId = Expression<Int64?>("account_id")
        self.status = Expression<Int?>("status")
        self.topic = Expression<String?>("topic")
        self.type = Expression<Int?>("type")
        self.visible = Expression<Int64?>("visible")
        self.created = Expression<Date?>("created")
        self.updated = Expression<Date?>("updated")
        self.read = Expression<Int?>("read")
        self.recv = Expression<Int?>("recv")
        self.seq = Expression<Int?>("seq")
        self.clear = Expression<Int?>("clear")
        self.maxDel = Expression<Int?>("max_del")
        self.accessMode = Expression<String?>("mode")
        self.defacs = Expression<String?>("defacs")
        self.lastUsed = Expression<Date?>("last_used")
        self.minLocalSeq = Expression<Int?>("min_local_seq")
        self.maxLocalSeq = Expression<Int?>("max_local_seq")
        self.nextUnsentSeq = Expression<Int?>("next_unsent_seq")
        self.tags = Expression<String?>("tags")
        self.pub = Expression<String?>("pub")
        self.priv = Expression<String?>("priv")
    }
    func destroyTable() {
        try! self.db.run(self.table!.drop(ifExists: true))
    }

    func createTable() {
        self.table = Table(TopicDb.kTableName)
        // Must succeed.
        try! self.db.run(self.table!.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(accountId)
            t.column(status)
            t.column(topic)
            t.column(type)
            t.column(visible)
            t.column(created)
            t.column(updated)

            t.column(read)
            t.column(recv)
            t.column(seq)
            t.column(clear)
            t.column(maxDel)

            t.column(accessMode)
            t.column(defacs)
            t.column(lastUsed)
            t.column(minLocalSeq)
            t.column(maxLocalSeq)
            t.column(nextUnsentSeq)

            t.column(tags)
            t.column(pub)
            t.column(priv)
        })
    }
    func deserializeTopic(topic: TopicProto, row: Row) {
        //
        var st = StoredTopic()
        st.id = row[self.id]
        st.status = row[self.status]
        st.lastUsed = row[self.lastUsed]
        st.minLocalSeq = row[self.minLocalSeq]
        st.maxLocalSeq = row[self.maxLocalSeq]
        st.nextUnsentId = row[self.nextUnsentSeq]

        topic.updated = row[self.updated]
        topic.read = row[self.read]
        topic.recv = row[self.recv]
        topic.seq = row[self.seq]
        topic.clear = row[self.clear]
        topic.maxDel = row[self.maxDel] ?? 0
        topic.tags = row[self.tags]?.components(separatedBy: ",")
        
        topic.accessMode = Acs.deserialize(from: row[self.accessMode])
        topic.defacs = Defacs.deserialize(from: row[self.defacs])
        topic.deserializePub(from: row[self.pub])
        topic.deserializePriv(from: row[self.priv])
        topic.payload = st
        /*
        
        
        topic.setRead(c.getInt(TopicDb.COLUMN_IDX_READ));
        topic.setRecv(c.getInt(TopicDb.COLUMN_IDX_RECV));
        topic.setSeq(c.getInt(TopicDb.COLUMN_IDX_SEQ));
        topic.setClear(c.getInt(TopicDb.COLUMN_IDX_CLEAR));
        topic.setMaxDel(c.getInt(TopicDb.COLUMN_IDX_MAX_DEL));
        
        topic.setTags(BaseDb.deserializeTags(c.getString(TopicDb.COLUMN_IDX_TAGS)));
        topic.setPub(BaseDb.deserialize(c.getString(TopicDb.COLUMN_IDX_PUBLIC)));
        topic.setPriv(BaseDb.deserialize(c.getString(TopicDb.COLUMN_IDX_PRIVATE)));
        
        topic.setAccessMode(BaseDb.deserializeMode(c.getString(TopicDb.COLUMN_IDX_ACCESSMODE)));
        topic.setDefacs(BaseDb.deserializeDefacs(c.getString(TopicDb.COLUMN_IDX_DEFACS)));
        
        topic.setLocal(st);
        */
    }
    func query() -> AnySequence<Row>? {
        return try? self.db.prepare(self.table!)
    }
    func readOne(for tinode: Tinode?, row: Row) -> TopicProto? {
        guard let tn = tinode, let topicName = row[self.topic] else {
            return nil
        }
        let t = tn.newTopic(for: topicName, with: nil)
        self.deserializeTopic(topic: t, row: row)
        return t
    }
    func insert(topic: TopicProto) -> Int64 {
        let lastUsed = Date()
        do {
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
                    pub <- topic.serializePub(),  // todo
                    priv <- topic.serializePriv()  // todo
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
        
    }
}
