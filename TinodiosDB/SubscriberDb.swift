//
//  SubscriberDb.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import SQLite
import TinodeSDK

public class StoredSubscription: Payload  {
    public var id: Int64? = nil
    public var topicId: Int64? = nil
    public var userId: Int64? = nil
    public var status: BaseDb.Status? = nil
}

enum SubscriberDbError: Error {
    case dbError(String)
}

public class SubscriberDb {
    public static let kTableName = "subscriptions"
    private let db: SQLite.Connection

    private var table: Table

    public let id: Expression<Int64>
    public var topicId: Expression<Int64?>
    public let userId: Expression<Int64?>
    public let status: Expression<Int?>
    public let mode: Expression<String?>
    public let updated: Expression<Date?>

    public let read: Expression<Int?>
    public let recv: Expression<Int?>
    public let clear: Expression<Int?>
    public let priv: Expression<String?>
    public let lastSeen: Expression<Date?>
    public let userAgent: Expression<String?>
    public let subscriptionClass: Expression<String>

    private let baseDb: BaseDb!

    init(_ database: SQLite.Connection, baseDb: BaseDb) {
        self.db = database
        self.baseDb = baseDb
        self.table = Table(SubscriberDb.kTableName)
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
        self.priv = Expression<String?>("priv")
        self.lastSeen = Expression<Date?>("last_seen")
        self.userAgent = Expression<String?>("user_agent")
        self.subscriptionClass = Expression<String>("subscription_class")
    }
    func destroyTable() {
        try! self.db.run(self.table.dropIndex(topicId, ifExists: true))
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
            t.column(mode)
            t.column(updated)
            //self.deleted =
            t.column(read)
            t.column(recv)
            t.column(clear)
            t.column(priv)
            t.column(lastSeen)
            t.column(userAgent)
            t.column(subscriptionClass)
        })
        try! self.db.run(self.table.createIndex(topicId, ifNotExists: true))
    }
    func insert(for topicId: Int64, with status: BaseDb.Status, using sub: SubscriptionProto) -> Int64 {
        var rowId: Int64 = -1
        do {
            try self.db.savepoint("SubscriberDb.insert") {
                let ss = StoredSubscription()
                let userDb = baseDb.userDb!
                ss.userId = userDb.getId(for: sub.user)
                if (ss.userId ?? -1) <= 0 {
                    ss.userId = userDb.insert(sub: sub)
                }
                // Still not okay?
                if (ss.userId ?? -1) <= 0 {
                    throw SubscriberDbError.dbError("failed to insert row into UserDb: \(String(describing: ss.userId))")
                }
                var setters = [Setter]()

                ss.topicId = topicId
                setters.append(self.topicId <- ss.topicId)
                setters.append(self.userId <- ss.userId)
                setters.append(self.mode <- sub.acs?.serialize())
                setters.append(self.updated <- sub.updated ?? Date())
                setters.append(self.status <- status.rawValue)
                ss.status = status
                setters.append(self.read <- sub.getRead)
                setters.append(self.recv <- sub.getRecv)
                setters.append(self.clear <- sub.getClear)
                setters.append(self.priv <- sub.serializePriv())
                if let seen = sub.seen {
                    setters.append(self.lastSeen <- seen.when)
                    setters.append(self.userAgent <- seen.ua)
                }
                setters.append(self.subscriptionClass <- String(describing: type(of: sub as Any)))
                rowId = try db.run(self.table.insert(setters))
                ss.id = rowId
                sub.payload = ss
            }
        } catch {
            BaseDb.log.error("SubscriberDb - insert operation failed: topicId = %lld, error = %@", topicId, error.localizedDescription)
            return -1
        }
        return rowId
    }
    func update(using sub: SubscriptionProto) -> Bool {
        guard let ss = sub.payload as? StoredSubscription, let recordId = ss.id, recordId >= 0 else {
            return false
        }
        let record = self.table.filter(self.id == recordId)
        var updated = 0
        do {
            try self.db.savepoint("SubscriberDb.update") {
                var status = ss.status!
                _ = baseDb.userDb!.update(sub: sub)
                var setters = [Setter]()
                setters.append(self.mode <- sub.acs?.serialize())
                setters.append(self.updated <- sub.updated)
                if status != .synced {
                    setters.append(self.status <- BaseDb.Status.synced.rawValue)
                    status = .synced
                }
                setters.append(self.read <- sub.getRead)
                setters.append(self.recv <- sub.getRecv)
                setters.append(self.clear <- sub.getClear)
                setters.append(self.priv <- sub.serializePriv())
                if let seen = sub.seen {
                    setters.append(self.lastSeen <- seen.when)
                    setters.append(self.userAgent <- seen.ua)
                }
                updated = try self.db.run(record.update(setters))
                ss.status = status
            }
        } catch {
            BaseDb.log.error("SubscriberDb - update operation failed: subId = %lld, error = %@", recordId, error.localizedDescription)
            return false
        }
        return updated > 0
    }
    func delete(recordId: Int64) -> Bool {
        let record = self.table.filter(self.id == recordId)
        do {
            return try self.db.run(record.delete()) > 0
        } catch {
            BaseDb.log.error("SubscriberDb - delete operation failed: subId = %lld, error = %@", recordId, error.localizedDescription)
            return false
        }
    }
    @discardableResult
    func deleteForTopic(topicId: Int64) -> Bool {
        let record = self.table.filter(self.topicId == topicId)
        do {
            return try self.db.run(record.delete()) > 0
        } catch {
            BaseDb.log.error("SubscriberDb - deleteForTopic operation failed: topicId = %lld, error = %@", topicId, error.localizedDescription)
            return false
        }
    }

    private func readOne(r: Row) -> SubscriptionProto? {
        guard let s = DefaultSubscription.createByName(name: r[self.subscriptionClass]) else { return nil }
        guard let udb = baseDb.userDb else { return nil }
        guard let tdb = baseDb.topicDb else { return nil }
        let ss = StoredSubscription()
        ss.id = r[self.id]
        ss.topicId = r[self.topicId]
        ss.userId = r[self.userId]
        ss.status = BaseDb.Status(rawValue: r[self.status] ?? 0) ?? .undefined

        s.acs = Acs.deserialize(from: r[self.mode])
        s.updated = r[self.updated]
        s.seq = r[tdb.seq]
        s.read = r[self.read]
        s.recv = r[self.recv]
        s.clear = r[self.clear]
        s.seen = LastSeen(when: r[self.lastSeen], ua: r[self.userAgent])
        s.user = r[udb.uid]
        s.topic = r[tdb.topic]
        s.deserializePub(from: r[udb.pub])
        s.deserializePriv(from: r[self.priv])
        s.payload = ss
        return s
    }

    func readAll(topicId: Int64) -> [SubscriptionProto]? {
        guard let userDb = baseDb.userDb else { return nil }
        guard let topicDb = baseDb.topicDb else { return nil }
        let joinedTable = self.table.select(
            self.table[self.id],
            self.topicId,
            self.userId,
            self.table[self.status],
            self.table[self.mode],
            self.table[self.updated],
            //self.deleted
            self.table[self.read],
            self.table[self.recv],
            self.table[self.clear],
            self.table[self.priv],
            self.lastSeen,
            self.userAgent,
            userDb.table[userDb.uid],
            userDb.table[userDb.pub],
            topicDb.table[topicDb.topic],
            topicDb.table[topicDb.seq],
            self.subscriptionClass)
            .join(.leftOuter, userDb.table, on: self.table[self.userId] == userDb.table[userDb.id])
            .join(.leftOuter, topicDb.table, on: self.table[self.topicId] == topicDb.table[topicDb.id])
            .filter(self.topicId == topicId)

        do {
            var subscriptions = [SubscriptionProto]()
            for row in try db.prepare(joinedTable) {
                if let s = self.readOne(r: row) {
                    subscriptions.append(s)
                } else {
                    BaseDb.log.error("SubscriberDb - readAll: topicId = %lld | failed to create subscription for %@", topicId, row[self.subscriptionClass])
                }
            }
            return subscriptions
        } catch {
            BaseDb.log.error("SubscriberDb - failed to read subscriptions: %@", error.localizedDescription)
            return nil
        }
    }

    func updateRead(for subId: Int64, with value: Int) -> Bool {
        return BaseDb.updateCounter(db: self.db, table: self.table,
                                    usingIdColumn: self.id, forId: subId,
                                    in: self.read, with: value)
    }

    func updateRecv(for subId: Int64, with value: Int) -> Bool {
        return BaseDb.updateCounter(db: self.db, table: self.table,
                                    usingIdColumn: self.id, forId: subId,
                                    in: self.recv, with: value)
    }
}
