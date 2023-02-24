//
//  TopicDb.swift
//  ios
//
//  Copyright © 2019-2022 Tinode. All rights reserved.
//

import Foundation
import SQLite
import TinodeSDK

public class StoredTopic: Payload {
    var id: Int64?
    var lastUsed: Date?
    var minLocalSeq: Int?
    var maxLocalSeq: Int?
    var status: BaseDb.Status = .undefined
    var nextUnsentId: Int?

    public static func isAllDataLoaded(topic: TopicProto?) -> Bool {
        guard let topic = topic else { return false }
        if (topic.seq ?? -1) == 0 { return true }
        guard let st = topic.payload as? StoredTopic else { return false }
        return (st.minLocalSeq ?? -1) == 1
    }
}

public class TopicDb {
    public static let kTableName = "topics"
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
    public let creds: Expression<String?>
    public let pub: Expression<String?>
    public let priv: Expression<String?>
    public let trusted: Expression<String?>

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
        self.creds = Expression<String?>("creds")
        self.pub = Expression<String?>("pub")
        self.priv = Expression<String?>("priv")
        self.trusted = Expression<String?>("trusted")
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
            t.column(creds)
            t.column(pub)
            t.column(priv)
            t.column(trusted)
        })
        try! db.run(self.table.createIndex(accountId, topic, unique: true, ifNotExists: true))
    }

    // Deletes all records from `topics` table.
    public func truncateTable() {
        try! self.db.run(self.table.delete())
    }

    public static func isUnsentSeq(seq: Int) -> Bool {
        return seq >= TopicDb.kUnsentIdStart
    }

    func deserializeTopic(topic: TopicProto, row: Row) {
        let st = StoredTopic()
        st.id = row[self.id]
        st.status = BaseDb.Status(rawValue: row[self.status] ?? 0) ?? .undefined
        st.lastUsed = row[self.lastUsed]
        st.minLocalSeq = row[self.minLocalSeq]
        st.maxLocalSeq = row[self.maxLocalSeq]
        st.nextUnsentId = row[self.nextUnsentSeq]

        topic.updated = row[self.updated]
        topic.touched = st.lastUsed
        topic.deleted = st.status == BaseDb.Status.deletedHard || st.status == BaseDb.Status.deletedSoft
        topic.read = row[self.read]
        topic.recv = row[self.recv]
        topic.seq = row[self.seq]
        topic.clear = row[self.clear]
        topic.maxDel = row[self.maxDel] ?? 0
        (topic as? MeTopicProto)?.deserializeCreds(from: row[self.creds])
        topic.tags = row[self.tags]?.components(separatedBy: ",")

        topic.accessMode = Acs.deserialize(from: row[self.accessMode])
        topic.defacs = Defacs.deserialize(from: row[self.defacs])
        topic.deserializePub(from: row[self.pub])
        topic.deserializePriv(from: row[self.priv])
        topic.deserializeTrusted(from: row[self.trusted])
        topic.payload = st
    }
    public func getId(topic: String?) -> Int64 {
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
            BaseDb.log.error("TopicDb - getNextUnusedSeq operation failed: topicId = %lld, error = %@", recordId, error.localizedDescription)
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
    func readOne(for tinode: Tinode?, withName topicName: String?) -> TopicProto? {
        guard let accountId = baseDb.account?.id else {
            return nil
        }
        if let row = try? db.pluck(self.table.filter(self.accountId == accountId && self.topic == topicName)) {
            return readOne(for: tinode, row: row)
        }
        return nil
    }
    func readOne(for tinode: Tinode?, row: Row) -> TopicProto? {
        guard let topicName = row[self.topic] else {
            return nil
        }
        let t = Tinode.newTopic(withTinode: tinode, forTopic: topicName)
        self.deserializeTopic(topic: t, row: row)
        return t
    }
    func insert(topic: TopicProto) -> Int64 {
        guard let accountId = baseDb.account?.id else {
            BaseDb.log.error("TopicDb.insert: account id is not defined.")
            return -1
        }
        do {
            // 1414213562 is Oct 25, 2014 05:06:02 UTC, incidentally equal to the first few digits of sqrt(2)
            let lastUsed = topic.touched ?? Date(timeIntervalSince1970: 1414213562)

            let tp = topic.topicType
            let tpv = tp.rawValue
            let status = topic.isNew ? BaseDb.Status.queued : BaseDb.Status.synced
            let rowid = try db.run(
                self.table.insert(
                    self.accountId <- accountId,
                    self.status <- status.rawValue,
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
                    creds <- (topic as? MeTopicProto)?.serializeCreds(),
                    pub <- topic.serializePub(),
                    priv <- topic.serializePriv(),
                    trusted <- topic.serializeTrusted()
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
            BaseDb.log.error("TopicDb - insert operation failed: error = %@", error.localizedDescription)
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
        if status == BaseDb.Status.queued && !topic.isNew {
            status = BaseDb.Status.synced
            setters.append(self.status <- status.rawValue)
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
        if let topic = topic as? MeTopicProto {
            setters.append(self.creds <- topic.serializeCreds())
        }
        setters.append(self.pub <- topic.serializePub())
        setters.append(self.priv <- topic.serializePriv())
        setters.append(self.trusted <- topic.serializeTrusted())
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
            BaseDb.log.error("TopicDb - update operation failed: topicId = %lld, error = %@", recordId, error.localizedDescription)
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
                BaseDb.log.error("TopicDb - msgReceived failed: topicId = %@, error = %@", recordId, error.localizedDescription)
                return false
            }
        }
        return true
    }
    func msgDeleted(topic: TopicProto, delId: Int, from loId: Int, to hiId: Int) -> Bool {
        guard let st = topic.payload as? StoredTopic, let recordId = st.id else {
            return false
        }
        var setters = [Setter]()
        if delId > topic.maxDel {
            setters.append(self.maxDel <- delId)
        }
        // If lowId is 0, all earlier messages are being deleted, set it to lowest possible value: 1.
        var loId = loId > 0 ? loId : 1
        // Upper bound is exclusive.
        // If hiId is zero all later messages are bing deleted, set it to highest possible value.
        var hiId = hiId > 1 ? hiId - 1 : (topic.seq ?? 0)

        // Expand the available range only when there is an overlap.
        // When minLocalSeq is 0 then there are no locally stored messages. Don't update minLocalSeq.
        if loId < (st.minLocalSeq ?? 0) && hiId >= (st.minLocalSeq ?? 0) {
            setters.append(self.minLocalSeq <- loId)
        } else {
            loId = -1
        }
        if hiId > (st.maxLocalSeq ?? 0) && loId <= (st.maxLocalSeq ?? 0) {
            setters.append(self.maxLocalSeq <- hiId)
        } else {
            hiId = -1
        }

        guard !setters.isEmpty else { return true }
        let record = self.table.filter(self.id == recordId)
        var success = false
        do {
            success = try self.db.run(record.update(setters)) > 0
            if success {
                if loId > 0 {
                    st.minLocalSeq = loId
                }
                if hiId > 0 {
                    st.maxLocalSeq = hiId
                }
            }
        } catch {
            BaseDb.log.error("TopicDb - msgDelivered failed: topicId = %lld, error = %@", recordId, error.localizedDescription)
        }
        return success
    }

    @discardableResult
    func delete(recordId: Int64) -> Bool {
        let record = self.table.filter(self.id == recordId)
        do {
            return try self.db.run(record.delete()) > 0
        } catch {
            BaseDb.log.error("TopicDb - delete failed: topicId = %lld, error = %@", recordId, error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func markDeleted(recordId: Int64) -> Bool {
        let record = self.table.filter(self.id == recordId)
        var setters: [Setter] = []
        setters.append(self.status <- BaseDb.Status.deletedHard.rawValue)
        do {
            return try self.db.run(record.update(setters)) > 0
        } catch {
            BaseDb.log.error("TopicDb - mark deleted failed: topicId = %lld, error = %@", recordId, error.localizedDescription)
            return false
        }
    }

    func deleteAll(forAccount accountId: Int64) -> Bool {
        // Delete from messages and subscribers where topicIds belong to accountId.
        guard let messageDb = self.baseDb.messageDb, let subscriberDb = self.baseDb.subscriberDb else { return false }
        // Using raw sql here because SQLite.swift doesn't support nested queries:
        // https://stackoverflow.com/questions/46033280/sqlite-swift-how-to-do-subquery
        let messageDbSql =
            "DELETE FROM " + MessageDb.kTableName +
            " WHERE " + messageDb.topicId.template + " IN (" +
            "SELECT " + self.id.template + " FROM " + TopicDb.kTableName +
            " WHERE " + self.accountId.template + " = ?)"
        let subscriberDbSql =
            "DELETE FROM " + SubscriberDb.kTableName +
            " WHERE " + subscriberDb.topicId.template + " IN (" +
            "SELECT " + self.id.template + " FROM " + TopicDb.kTableName +
            " WHERE " + self.accountId.template + " = ?)"
        let topics = self.table.filter(self.accountId == accountId)
        do {
            try self.db.run(messageDbSql, accountId)
            try self.db.run(subscriberDbSql, accountId)
            try self.db.run(topics.delete())
        } catch {
            BaseDb.log.error("TopicDb - deleteAll(forAccount) failed: accountId = %lld, error = %@", accountId, error.localizedDescription)
            return false
        }
        return true
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
