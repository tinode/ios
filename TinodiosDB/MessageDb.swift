//
//  MessageDb.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import SQLite
import TinodeSDK

enum MessageDbError: Error {
    case dataError(String)
    case dbError(String)
}

public class MessageDb {
    private static let kTableName = "messages"
    private let db: SQLite.Connection

    public var table: Table

    public let id: Expression<Int64>
    public let topicId: Expression<Int64?>
    public let userId: Expression<Int64?>
    public let status: Expression<Int?>
    public let sender: Expression<String?>
    public let ts: Expression<Date?>
    public let seq: Expression<Int?>
    public let head: Expression<String?>
    public let content: Expression<String?>

    private let baseDb: BaseDb!

    init(_ database: SQLite.Connection, baseDb: BaseDb) {
        self.db = database
        self.baseDb = baseDb
        self.table = Table(MessageDb.kTableName)
        self.id = Expression<Int64>("id")
        self.topicId = Expression<Int64?>("topic_id")
        self.userId = Expression<Int64?>("user_id")
        self.status = Expression<Int?>("status")
        self.sender = Expression<String?>("sender")
        self.ts = Expression<Date?>("ts")
        self.seq = Expression<Int?>("seq")
        self.head = Expression<String?>("head")
        self.content = Expression<String?>("content")
    }
    func destroyTable() {
        try! self.db.run(self.table.dropIndex(topicId, ts, ifExists: true))
        try! self.db.run(self.table.drop(ifExists: true))
    }
    func createTable() {
        let userDb = baseDb.userDb!
        let topicDb = baseDb.topicDb!
        // Must succeed.
        try! self.db.run(self.table.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(topicId, references: topicDb.table, topicDb.id)
            t.column(userId, references: userDb.table, userDb.id)
            t.column(status)
            t.column(sender)
            t.column(ts)
            t.column(seq)
            t.column(head)
            t.column(content)
        })
        try! self.db.run(self.table.createIndex(topicId, ts, ifNotExists: true))
    }
    func insert(topic: TopicProto?, msg: StoredMessage?) -> Int64 {
        guard let topic = topic, let msg = msg else {
            return -1
        }
        if msg.msgId > 0 {
            // Already saved.
            return msg.msgId
        }

        do {
            try db.savepoint("MessageDb.insert") {
                guard let tdb = baseDb.topicDb else {
                    throw MessageDbError.dbError("no topicDb in messageDb insert")
                }
                if (msg.topicId ?? -1) <= 0 {
                    msg.topicId = tdb.getId(topic: msg.topic)
                }
                guard let udb = baseDb.userDb else {
                    throw MessageDbError.dbError("no userDb in messageDb insert")
                }
                if (msg.userId ?? -1) <= 0 {
                    msg.userId = udb.getId(for: msg.from)
                }
                guard let topicId = msg.topicId, let userId = msg.userId, topicId >= 0, userId >= 0 else {
                    throw MessageDbError.dataError("Failed to insert row into MessageDb: topicId = \(String(describing: msg.topicId)), userId = \(String(describing: msg.userId))")
                }
                var status: Int = BaseDb.kStatusUndefined
                if let seq = msg.seq, seq > 0 {
                    status = BaseDb.kStatusSynced
                } else {
                    msg.seq = tdb.getNextUnusedSeq(topic: topic)
                    status = (msg.status == nil || msg.status == BaseDb.kStatusUndefined) ? BaseDb.kStatusQueued : msg.status!
                }
                var setters = [Setter]()
                setters.append(self.topicId <- topicId)
                setters.append(self.userId <- userId)
                setters.append(self.status <- status)
                setters.append(self.sender <- msg.from)
                setters.append(self.ts <- msg.ts)
                setters.append(self.seq <- msg.seq)
                if let h = msg.head {
                    setters.append(self.head <- Tinode.serializeObject(h))
                }
                setters.append(self.content <- msg.content?.serialize())
                msg.msgId = try db.run(self.table.insert(setters))
            }
            return msg.msgId
        } catch {
            BaseDb.log.error("MessageDb - insert operation failed: %@", error.localizedDescription)
            return -1
        }
    }
    func updateStatusAndContent(msgId: Int64, status: Int?, content: Drafty?) -> Bool {
        let record = self.table.filter(self.id == msgId)
        var setters = [Setter]()
        if status != BaseDb.kStatusUndefined {
            setters.append(self.status <- status!)
        }
        if content != nil {
            setters.append(self.content <- content!.serialize())
        }
        if !setters.isEmpty {
            do {
                return try self.db.run(record.update(setters)) > 0
            } catch {
                BaseDb.log.error("MessageDb - update status operation failed: msgId = %lld, error = %@", msgId, error.localizedDescription)
            }
        }
        return false
    }
    func delivered(msgId: Int64, ts: Date?, seq: Int?) -> Bool {
        let record = self.table.filter(self.id == msgId)
        do {
            return try self.db.run(record.update(
                self.status <- BaseDb.kStatusSynced,
                self.ts <- ts,
                self.seq <- seq)) > 0
        } catch {
            BaseDb.log.error("MessageDb - update delivery operation failed: msgId = %lld, error = %@", msgId, error.localizedDescription)
            return false
        }
    }
    @discardableResult
    func delete(topicId: Int64, from loId: Int?, to hiId: Int?) -> Bool {
        let startId = loId ?? 0
        var endId = hiId ?? Int.max
        if endId == 0 {
            endId = startId
        }
        // delete from messages where topic_id = topicId and seq between startId (inclusive) and endId (non-inclusive).
        let rows = self.table.filter(self.topicId == topicId && startId <= self.seq && self.seq < endId)
        do {
            return try self.db.run(rows.delete()) > 0
        } catch {
            BaseDb.log.error("MessageDb - delete operation failed: topicId = %lld, error = %@", topicId, error.localizedDescription)
            return false
        }
    }
    @discardableResult
    func markDeleted(topicId: Int64, from loId: Int?, to hiId: Int?, hard: Bool) -> Bool {
        let startId = loId ?? 0
        var endId = hiId ?? Int.max
        if endId == 0 {
            endId = startId + 1
        }
        do {
            var updateResult = false
            var deleteResult = false
            try db.savepoint("MessageDb.markDeleted") {
                let rowsToMarkDeleted = self.table.filter(
                    self.topicId == topicId && startId <= self.seq && self.seq < endId && self.status == BaseDb.kStatusSynced)
                updateResult = try self.db.run(rowsToMarkDeleted.update(
                    self.status <- hard ? BaseDb.kStatusDeletedHard : BaseDb.kStatusDeletedSoft)) > 0
                let rowsToDelete = self.table.filter(
                    self.topicId == topicId && startId <= self.seq && self.seq < endId && self.status <= BaseDb.kStatusQueued)
                deleteResult = try self.db.run(rowsToDelete.delete()) > 0
            }
            return updateResult && deleteResult
        } catch {
            BaseDb.log.error("MessageDb - markDeleted operation failed: topicId = %lld, error = %@", topicId, error.localizedDescription)
            return false
        }
    }
    func delete(msgId: Int64) -> Bool {
        let record = self.table.filter(self.id == msgId)
        do {
            return try self.db.run(record.delete()) > 0
        } catch {
            BaseDb.log.error("MessageDb - delete operation failed: msgId = %lld, error = %@", msgId, error.localizedDescription)
            return false
        }
    }
    private func readOne(r: Row) -> StoredMessage {
        let sm = StoredMessage()
        sm.msgId = r[self.id]
        sm.topicId = r[self.topicId]
        sm.userId = r[self.userId]
        sm.status = r[self.status]
        sm.from = r[self.sender]
        sm.ts = r[self.ts]
        sm.seq = r[self.seq]
        sm.head = Tinode.deserializeObject(from: r[self.head])
        sm.content = Drafty.deserialize(from: r[self.content])
        return sm
    }
    public func query(topicId: Int64?, pageCount: Int, pageSize: Int) -> [StoredMessage]? {
        let queryTable = self.table
            .filter(
                self.topicId == topicId &&
                self.status <= BaseDb.kStatusVisible)
            .order(self.ts.desc)
            .limit(pageCount * pageSize)
        do {
            var messages = [StoredMessage]()
            for row in try db.prepare(queryTable) {
                let sm = self.readOne(r: row)
                messages.append(sm)
            }
            return messages
        } catch {
            BaseDb.log.error("MessageDb - query operation failed: topicId = %lld, error = %@", topicId ?? -1, error.localizedDescription)
            return nil
        }
    }
    func query(msgId: Int64?) -> StoredMessage? {
        guard let msgId = msgId else { return nil }
        let record = self.table.filter(self.id == msgId)
        if let row = try? db.pluck(record) {
            return self.readOne(r: row)
        }
        return nil
    }
    func queryDeleted(topicId: Int64?, hard: Bool) -> [Int]? {
        guard let topicId = topicId else { return nil }
        let status = hard ? BaseDb.kStatusDeletedHard : BaseDb.kStatusDeletedSoft
        let queryTable = self.table
            .filter(
                self.topicId == topicId &&
                self.status == status)
            .select(self.seq)
            .order(self.ts)
        do {
            var seqIds = [Int]()
            for row in try db.prepare(queryTable) {
                if let sm = row[self.seq] {
                    seqIds.append(sm)
                }
            }
            return seqIds
        } catch {
            BaseDb.log.error("MessageDb - queryDeleted operation failed: topicId = %lld, error = %@", topicId, error.localizedDescription)
            return nil
        }
    }
    func queryUnsent(topicId: Int64?) -> [Message]? {
        let queryTable = self.table
            .filter(
                self.topicId == topicId &&
                self.status == BaseDb.kStatusQueued)
            .order(self.ts)
        do {
            var messages = [StoredMessage]()
            for row in try db.prepare(queryTable) {
                let sm = self.readOne(r: row)
                messages.append(sm)
            }
            return messages
        } catch {
            BaseDb.log.error("MessageDb - queryUnsent operation failed: topicId = %lld, error = %@", topicId ?? -1, error.localizedDescription)
            return nil
        }
    }
}
