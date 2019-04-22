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

class MessageDb {
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
    public let content: Expression<String?>

    init(_ database: SQLite.Connection) {
        self.db = database
        self.table = Table(MessageDb.kTableName)
        self.id = Expression<Int64>("id")
        self.topicId = Expression<Int64?>("topic_id")
        self.userId = Expression<Int64?>("user_id")
        self.status = Expression<Int?>("status")
        self.sender = Expression<String?>("sender")
        self.ts = Expression<Date?>("ts")
        self.seq = Expression<Int?>("seq")
        self.content = Expression<String?>("content")
    }
    func destroyTable() {
        try! self.db.run(self.table.dropIndex(topicId, ts, ifExists: true))
        try! self.db.run(self.table.drop(ifExists: true))
    }
    func createTable() {
        let userDb = BaseDb.getInstance().userDb!
        let topicDb = BaseDb.getInstance().topicDb!
        // Must succeed.
        try! self.db.run(self.table.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(topicId, references: topicDb.table, topicDb.id)
            t.column(userId, references: userDb.table, userDb.id)
            t.column(status)
            t.column(sender)
            t.column(ts)
            t.column(seq)
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
                guard let tdb = BaseDb.getInstance().topicDb else {
                    throw MessageDbError.dbError("no topicDb in messageDb insert")
                }
                if (msg.topicId ?? -1) <= 0 {
                    msg.topicId = tdb.getId(topic: msg.topic)
                }
                guard let udb = BaseDb.getInstance().userDb else {
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
                setters.append(self.content <- msg.content)
                msg.msgId = try db.run(self.table.insert(setters))
            }
            return msg.msgId
        } catch {
            print("Failed to save message: \(error)")
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
            setters.append(self.content <- content!)
        }
        if !setters.isEmpty {
            do {
                return try self.db.run(record.update(setters)) > 0
            } catch {
                print("update failed: \(error)")
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
            print("update failed: \(error)")
            return false
        }
    }
    func delete(msgId: Int64) -> Bool {
        let record = self.table.filter(self.id == msgId)
        do {
            return try self.db.run(record.delete()) > 0
        } catch {
            print("delete failed: \(error)")
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
        sm.content = r[self.content]
        return sm
    }
    func query(topicId: Int64?, pageCount: Int, pageSize: Int) -> [StoredMessage]? {
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
            print("failed to read messages \(error)")
            return nil
        }
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
            print("Topic: \(topicId) failed to read deleted messages \(error)")
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
            print("failed to read messages \(error)")
            return nil
        }
    }
}
