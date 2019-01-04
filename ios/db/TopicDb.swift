//
//  TopicDb.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import SQLite

public struct StoredTopic: Payload {
    var id: Int64? = nil
    var lastUsed: Date? = nil
    var minLocalSeq: Int? = nil
    var maxLocalSeq: Int? = nil
    var status: Int = BaseDb.kStatusUndefined
    var nextUnsentId: Int? = nil
}

public class TopicDb {
    private static let kTableName = "topics"
    private static let kUnsentIdStart = 2000000000
    private let db: SQLite.Connection
    
    public var table: Table? = nil

    public let id: Expression<Int64>
    public let accountId: Expression<Int64?>
    public let status: Expression<Int?>
    public let topic: Expression<String?>
    public let type: Expression<Int?>
    public let visible: Expression<Int64?>
    public let created: Expression<Date?>
    public let updated: Expression<Date?>
    public let read: Expression<Int?>
    public let recv: Expression<Int?>
    public let seq: Expression<Int?>
    public let clear: Expression<Int?>
    public let maxDel: Expression<Int?>
    public let accessMode: Expression<String?>
    public let defacs: Expression<String?>
    public let lastUsed: Expression<Date?>
    public let minLocalSeq: Expression<Int?>
    public let maxLocalSeq: Expression<Int?>
    public let nextUnsentSeq: Expression<Int?>
    public let tags: Expression<String?>
    public let pub: Expression<String?>
    public let priv: Expression<String?>
    
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
        try! self.db.run(self.table!.dropIndex(accountId))
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
        try! db.run(self.table!.createIndex(accountId, unique: true, ifNotExists: true))
    }
    func deserializeTopic(topic: TopicProto, row: Row) {
        //
        var st = StoredTopic()
        st.id = row[self.id]
        st.status = row[self.status] ?? BaseDb.kStatusUndefined
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
                    pub <- topic.serializePub(),
                    priv <- topic.serializePriv()
                ))
            if rowid > 0 {
                let st = StoredTopic(
                    id: rowid, lastUsed: lastUsed,
                    minLocalSeq: nil, maxLocalSeq: nil,
                    status: BaseDb.kStatusUndefined,
                    nextUnsentId: TopicDb.kUnsentIdStart)
                topic.payload = st
            }
            print("inserted id: \(rowid)")
            return rowid
        } catch {
            print("insertion failed: \(error)")
            return -1
        }
        
    }
    func update(topic: TopicProto) -> Bool {
        guard var st = topic.payload as? StoredTopic, let recordId = st.id else {
            return false
        }
        guard let record = self.table?.filter(self.id == recordId) else {
            return false
        }
        var setters = [Setter]()
        var status = st.status
        if status == BaseDb.kStatusQueued && !topic.isNew {
            status = BaseDb.kStatusSynced
            setters.append(self.status <- status)
            setters.append(self.topic <- topic.name)
        }
        if let updated = topic.updated {
            setters.append(self.updated <- updated)
        }
        setters.append(self.read <- topic.read)
        setters.append(self.recv <- topic.recv)
        setters.append(self.seq <- topic.seq)
        setters.append(self.clear <- topic.clear)
        setters.append(self.accessMode <- topic.accessMode?.serialize())
        setters.append(self.defacs <- topic.defacs?.serialize())
        setters.append(self.tags <- topic.tags?.joined(separator: ","))
        setters.append(self.pub <- topic.serializePub())
        setters.append(self.priv <- topic.serializePriv())
        let lastUsed = Date()
        setters.append(self.lastUsed <- lastUsed)
        do {
            if try self.db.run(record.update(setters)) > 0 {
                st.lastUsed = lastUsed
                st.status = status
                return true
            }
        } catch {
            print("update failed: \(error)")
        }
        return false
    }
    func msgReceived(topic: TopicProto, ts: Date, seq: Int) -> Bool {
        guard var st = topic.payload as? StoredTopic, let recordId = st.id else {
            return false
        }
        var setters = [Setter]()
        var updateMaxLocalSeq = false
        if seq > (st.maxLocalSeq ?? -1) {
            setters.append(self.maxLocalSeq <- seq)
            setters.append(self.recv <- seq)
            updateMaxLocalSeq = true
        }
        var updateMinLocalSeq = false
        if seq > 0 && (st.minLocalSeq == 0 || seq < (st.minLocalSeq ?? Int.max)) {
            setters.append(self.minLocalSeq <- seq)
            updateMinLocalSeq = true
        }
        if seq > (topic.seq ?? -1) {
            setters.append(self.seq <- seq)
        }
        var updateLastUsed = false
        if let lastUsed = st.lastUsed, lastUsed < ts {
            setters.append(self.lastUsed <- ts)
            updateLastUsed = true
        }
        if setters.count > 0 {
            guard let record = self.table?.filter(self.id == recordId) else {
                return false
            }
            do {
                if try self.db.run(record.update(setters)) > 0 {
                    if updateLastUsed { st.lastUsed = ts }
                    if updateMinLocalSeq { st.minLocalSeq = seq }
                    if updateMaxLocalSeq { st.maxLocalSeq = seq }
                }
            } catch {
                print("msg received failed: \(error)")
                return false
            }
        }
        return true
    }
    func msgDeleted(topic: TopicProto, delId: Int) -> Bool {
        guard let st = topic.payload as? StoredTopic, let recordId = st.id else {
            return false
        }
        if delId > topic.maxDel {
            guard let record = self.table?.filter(self.id == recordId) else {
                return false
            }
            do {
                return try self.db.run(record.update(self.maxDel <- delId)) > 0
            } catch {
                print("msgDeleted failed: \(error)")
                return false
            }
        }
        return true
    }
    @discardableResult
    func delete(recordId: Int64) -> Bool {
        guard let record = self.table?.filter(self.id == recordId) else {
            return false
        }
        do {
            return try self.db.run(record.delete()) > 0
        } catch {
            print("delete failed: \(error)")
            return false
        }
    }
    private func updateCounter(for topicId: Int64, in column: Expression<Int?>, with value: Int) -> Bool{
        guard let record = self.table?.filter(self.id == topicId && column < value) else {
            return false
        }
        do {
            return try self.db.run(record.update(column <- value)) > 0
        } catch {
            print("updateCounter failed: \(error)")
            return false
        }
    }
    func updateRead(for topicId: Int64, with value: Int) -> Bool {
        /*
        guard let record = self.table?.filter(self.id == topicId && self.read < value) else {
            return false
        }
        do {
            return try self.db.run(record.update(self.read <- value)) > 0
        } catch {
            print("updateRead failed: \(error)")
            return false
        }
        */
        return self.updateCounter(for: topicId, in: self.read, with: value)
    }
    func updateRecv(for topicId: Int64, with value: Int) -> Bool {
        return self.updateCounter(for: topicId, in: self.recv, with: value)
    }
}
