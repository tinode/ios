//
//  EditHistoryDb.swift
//  TinodiosDB
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import SQLite
import TinodeSDK

public struct EditHistoryRecord {
    public var id: Int64 = 0
    public var topicId: Int64 = 0
    public var when: Date?
    public var origSeq: Int?
    public var oldSeq: Int?
    public var newSeq: Int?
}

enum EditHistoryDbError: Error {
    case dbError(String)
}

// The table contains:
// * messages (both synchronized and not yet synchronized with the server).
// * message deletion markers (synchronized and not yet synchronized).
public class EditHistoryDb {
    public static let kTableName = "edit_history"
    private let db: SQLite.Connection

    public var table: Table

    public let id: Expression<Int64>
    // Topic ID, references topics.id
    public let topicId: Expression<Int64?>
    // Timestamp when the record was created.
    public let replacedWhen: Expression<Date?>
    // Original seq value: if one message was edited several times, possibly recursively,
    // this is the seq ID of the very first message.
    public let origSeq: Expression<Int?>
    // The seq of the old message.
    public let oldSeq: Expression<Int?>
    // The seq of the new message.
    public let newSeq: Expression<Int?>
    // Old headers.
    public let head: Expression<String?>
    // Old content.
    public let content: Expression<String?>

    private let baseDb: BaseDb!

    init(_ database: SQLite.Connection, baseDb: BaseDb) {
        self.db = database
        self.baseDb = baseDb
        self.table = Table(EditHistoryDb.kTableName)

        self.id = Expression<Int64>("id")
        self.topicId = Expression<Int64?>("topic_id")
        self.replacedWhen = Expression<Date?>("replaced_when")
        self.origSeq = Expression<Int?>("orig_seq")
        self.oldSeq = Expression<Int?>("old_seq")
        self.newSeq = Expression<Int?>("new_seq")
        self.head = Expression<String?>("head")
        self.content = Expression<String?>("content")
    }
    func destroyTable() {
        try! self.db.run(self.table.dropIndex(topicId, origSeq, ifExists: true))
        try! self.db.run(self.table.dropIndex(topicId, newSeq, ifExists: true))
        try! self.db.run(self.table.drop(ifExists: true))
    }
    func createTable() {
        let topicDb = baseDb.topicDb!
        // Must succeed.
        try! self.db.run(self.table.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(topicId, references: topicDb.table, topicDb.id)
            t.column(replacedWhen)
            t.column(origSeq)
            t.column(oldSeq)
            t.column(newSeq)
            t.column(head)
            t.column(content)
        })
        try! self.db.run(self.table.createIndex(topicId, origSeq, ifNotExists: true))
        try! self.db.run(self.table.createIndex(topicId, newSeq, ifNotExists: true))
    }

    private func get(forTopic topicId: Int64, forOldSeqId oldSeq: Int) -> EditHistoryRecord? {
        if let row = try? db.pluck(self.table.filter(self.topicId == topicId && self.oldSeq == oldSeq)) {
            return EditHistoryRecord(
                id: row[self.id],
                topicId: topicId,
                when: row[self.replacedWhen],
                origSeq: row[self.origSeq],
                oldSeq: oldSeq,
                newSeq: row[self.newSeq]
            )
        }
        return nil
    }

    internal func upsert(onTopicId topicId: Int64, replacedMsg msg: StoredMessage?, withOrigSeq origSeq: Int?, forNewSeq newSeq: Int?, replacedAt when: Date?) throws {

        var historyRec: EditHistoryRecord!
        if let origSeq = origSeq, let prev = self.get(forTopic: topicId, forOldSeqId: origSeq) {
            // Record exists: update it with the values from the message.
            // msg must not be null in this case.
            let record = self.table.filter(self.id == prev.id)
            var setters = [Setter]()
            setters.append(self.origSeq <- msg?.seq)
            setters.append(self.head <- Tinode.serializeObject(msg?.head))
            setters.append(self.content <- msg?.content?.serialize())
            do {
                try self.db.run(record.update(setters))
            } catch {
                BaseDb.log.error("EditHistoryDb - update record operation failed: msgId = %lld, error = %@", prev.id, error.localizedDescription)
                throw EditHistoryDbError.dbError("EditHistoryDb update existing error: \(error)")
            }
            historyRec = prev
        } else {
            historyRec = EditHistoryRecord()
            // No record found, create.
            // oldMsg could be nil.
            var setters = [Setter]()
            setters.append(self.topicId <- topicId)
            setters.append(self.replacedWhen <- when)
            setters.append(self.origSeq <- origSeq)
            setters.append(self.oldSeq <- origSeq)
            setters.append(self.newSeq <- newSeq)
            setters.append(self.head <- Tinode.serializeObject(msg?.head))
            setters.append(self.content <- msg?.content?.serialize())

            do {
                historyRec.id = try db.run(self.table.insert(setters))
            } catch {
                BaseDb.log.error("EditHistoryDb - insert record operation failed: topicId = %lld, origSeq = %d, error = %@",
                                 topicId, (origSeq ?? -1), error.localizedDescription)
                throw EditHistoryDbError.dbError("EditHistoryDb insertion error: \(error)")
            }
        }
        if let msg = msg, let origId = msg.replacesSeq, origId < (historyRec.oldSeq ?? 0) {
            let record = self.table.filter(self.topicId == topicId && self.origSeq == historyRec.oldSeq)
            do {
                try self.db.run(record.update(self.origSeq <- origId))
            } catch {
                BaseDb.log.error("EditHistoryDb - update record operation failed: msgId = %lld, error = %@", historyRec.id, error.localizedDescription)
                throw EditHistoryDbError.dbError("EditHistoryDb update error: \(error)")
            }
        }
    }
}
