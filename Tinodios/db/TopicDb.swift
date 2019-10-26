//
//  TopicDb.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import SQLite
import TinodeSDK

public class StoredTopic: Payload {
    var id: Int64? = nil
    var lastUsed: Date? = nil
    var minLocalSeq: Int? = nil
    var maxLocalSeq: Int? = nil
    var status: Int = BaseDb.kStatusUndefined
    var nextUnsentId: Int? = nil

    static func isAllDataLoaded(topic: TopicProto?) -> Bool {
        guard let topic = topic else { return false }
        if (topic.seq ?? -1) == 0 { return true }
        guard let st = topic.payload as? StoredTopic else { return false }
        return (st.minLocalSeq ?? -1) == 1
    }
}

public class TopicDb {
    private static let kTableName = "topics"
    private static let kUnsentIdStart = 2000000000
    private let db: SQLite.Connection

    public var table: Table

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

    private let baseDb: BaseDb!

    init(_ database: SQLite.Connection, baseDb: BaseDb) {
        self.db = database
        self.baseDb = baseDb
        self.table = Table(TopicDb.kTableName)
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
        try! self.db.run(self.table.dropIndex(accountId, topic, ifExists: true))
        try! self.db.run(self.table.drop(ifExists: true))
    }

    func createTable() {
        let accountDb = baseDb.accountDb!
        // Must succeed.
        try! self.db.run(self.table.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(accountId, references: accountDb.table, accountDb.id)
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
        try! db.run(self.table.createIndex(accountId, topic, unique: true, ifNotExists: true))
    }
    func deserializeTopic(topic: TopicProto, row: Row) {
        let st = StoredTopic()
        st.id = row[self.id]
        st.status = row[self.status] ?? BaseDb.kStatusUndefined
        st.lastUsed = row[self.lastUsed]
        st.minLocalSeq = row[self.minLocalSeq]
        st.maxLocalSeq = row[self.maxLocalSeq]
        st.nextUnsentId = row[self.nextUnsentSeq]

        topic.updated = row[self.updated]
        topic.touched = st.lastUsed
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
    }
    func getId(topic: String?) -> Int64 {
        guard let topic = topic else {
            return -1
        }
        if let row = try? db.pluck(self.table.select(self.id).filter(self.accountId
            == baseDb.account?.id && self.topic == topic)) {
            return row[self.id]
        }
        return -1
    }
    func getNextUnusedSeq(topic: TopicProto) -> Int {
        guard let st = topic.payload as? StoredTopic, let recordId = st.id else { return -1 }
        let record = self.table.filter(self.id == recordId)
        st.nextUnsentId = (st.nextUnsentId ?? 0) + 1
        var setters = [Setter]()
        setters.append(self.nextUnsentSeq <- st.nextUnsentId)
        do {
            if try self.db.run(record.update(setters)) > 0 {
                return st.nextUnsentId!
            }
        } catch {
            Cache.log.error("TopicDb - getNextUnusedSeq operation failed: topicId = %lld, error = %@", recordId, error.localizedDescription)
        }
        return -1
    }
    func query() -> AnySequence<Row>? {
        guard let accountId = baseDb.account?.id else {
            return nil
        }
        let topics = self.table.filter(self.accountId == accountId)
        return try? self.db.prepare(topics)
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
        do {
            // 1414213562 is Oct 25, 2014 05:06:02 UTC, incidentally equal to the first few digits of sqrt(2)
            let lastUsed = topic.touched ?? Date(timeIntervalSince1970: 1414213562)

            let tp = topic.topicType
            let tpv = tp.rawValue
            let accountId = baseDb.account!.id
            let status = topic.isNew ? BaseDb.kStatusQueued : BaseDb.kStatusSynced
            let rowid = try db.run(
                self.table.insert(
                    self.accountId <- accountId,
                    self.status <- status,
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
                let st = StoredTopic()
                st.id = rowid
                st.lastUsed = lastUsed
                st.minLocalSeq = nil
                st.maxLocalSeq = nil
                st.status = status
                st.nextUnsentId = TopicDb.kUnsentIdStart
                topic.payload = st
            }
            return rowid
        } catch {
            Cache.log.error("TopicDb - insert operation failed: error = %@", error.localizedDescription)
            return -1
        }
    }
    func update(topic: TopicProto) -> Bool {
        guard let st = topic.payload as? StoredTopic, let recordId = st.id else {
            return false
        }
        let record = self.table.filter(self.id == recordId)
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
        if let touched = topic.touched {
            setters.append(self.lastUsed <- touched)
        }
        do {
            if try self.db.run(record.update(setters)) > 0 {
                if topic.touched != nil {
                    st.lastUsed = topic.touched
                }
                st.status = status
                return true
            }
        } catch {
            Cache.log.error("TopicDb - update operation failed: topicId = %lld, error = %@", recordId, error.localizedDescription)
        }
        return false
    }
    func msgReceived(topic: TopicProto, ts: Date, seq: Int) -> Bool {
        guard let st = topic.payload as? StoredTopic, let recordId = st.id else {
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
            let record = self.table.filter(self.id == recordId)
            do {
                if try self.db.run(record.update(setters)) > 0 {
                    if updateLastUsed { st.lastUsed = ts }
                    if updateMinLocalSeq { st.minLocalSeq = seq }
                    if updateMaxLocalSeq { st.maxLocalSeq = seq }
                }
            } catch {
                Cache.log.error("TopicDb - msgReceived operation failed: topicId = %@, error = %@", recordId, error.localizedDescription)
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
            let record = self.table.filter(self.id == recordId)
            do {
                return try self.db.run(record.update(self.maxDel <- delId)) > 0
            } catch {
                Cache.log.error("TopicDb - msgDelivered operation failed: topicId = %lld, error = %@", recordId, error.localizedDescription)
                return false
            }
        }
        return true
    }
    @discardableResult
    func delete(recordId: Int64) -> Bool {
        let record = self.table.filter(self.id == recordId)
        do {
            return try self.db.run(record.delete()) > 0
        } catch {
            Cache.log.error("TopicDb - delete operation failed: topicId = %lld, error = %@", recordId, error.localizedDescription)
            return false
        }
    }

    func updateRead(for topicId: Int64, with value: Int) -> Bool {
        return BaseDb.updateCounter(db: self.db, table: self.table,
                                    usingIdColumn: self.id, forId: topicId,
                                    in: self.read, with: value)
    }

    func updateRecv(for topicId: Int64, with value: Int) -> Bool {
        return BaseDb.updateCounter(db: self.db, table: self.table,
                                    usingIdColumn: self.id, forId: topicId,
                                    in: self.recv, with: value)
    }
}
