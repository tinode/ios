//
//  SubscriberDb.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import SQLite

class StoredSubscription: Payload  {
    var id: Int64? = nil
    var topicId: Int64? = nil
    var userId: Int64? = nil
    var status: Int? = nil
}

enum SubscriberDbError: Error {
    case dbError(String)
}

class SubscriberDb {
    private static let kTableName = "subscriptions"
    private let db: SQLite.Connection
    
    private var table: Table? = nil
    
    public let id: Expression<Int64>
    public var topicId: Expression<Int64?>
    public let userId: Expression<Int64?>
    public let status: Expression<Int?>
    public let mode: Expression<String?>
    public let updated: Expression<Date?>
    //public let deleted:
    public let read: Expression<Int?>
    public let recv: Expression<Int?>
    public let clear: Expression<Int?>
    public let lastSeen: Expression<Date?>
    public let userAgent: Expression<String?>
    public let subscriptionClass: Expression<String>

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
        self.subscriptionClass = Expression<String>("subscription_class")
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
            t.column(subscriptionClass)
        })
        try! self.db.run(self.table!.createIndex(topicId, ifNotExists: true))
    }
    func insert(for topicId: Int64, with status: Int, using sub: SubscriptionProto) -> Int64 {
        var rowId: Int64 = -1
        do {
            try self.db.transaction {
                let ss = StoredSubscription()
                ss.userId = BaseDb.getInstance().userDb?.getId(for: sub.user)
                if (ss.userId ?? -1) <= 0 {
                    ss.userId = BaseDb.getInstance().userDb?.insert(sub: sub)
                }
                // Still not okay?
                if (ss.userId ?? -1) <= 0 {
                    throw SubscriberDbError.dbError("failed to insert row into UserDb: \(String(describing: ss.userId))")
                }
                var setters = [Setter]()
                
                ss.topicId = topicId
                setters.append(self.topicId <- ss.topicId)
                setters.append(self.userId <- ss.userId)
                ss.status = status
                setters.append(self.mode <- sub.acs?.serialize())
                setters.append(self.updated <- sub.updated ?? Date())
                setters.append(self.read <- sub.getRead)
                setters.append(self.recv <- sub.getRecv)
                setters.append(self.clear <- sub.getClear)
                if let seen = sub.seen {
                    setters.append(self.lastSeen <- seen.when)
                    setters.append(self.userAgent <- seen.ua)
                }
                setters.append(self.subscriptionClass <-                  String(describing: type(of: sub as Any)))
                rowId = try db.run(self.table!.insert(setters))
                ss.id = rowId
                sub.payload = ss
            }
        } catch {
            print("SubscriberDb insertion failed: \(error)")
            return -1
        }
        return rowId
    }
    func update(using sub: SubscriptionProto) -> Bool {
        guard let ss = sub.payload as? StoredSubscription, let recordId = ss.id, recordId >= 0 else {
            return false
        }
        guard let record = self.table?.filter(self.id == recordId) else {
            return false
        }
        var updated = 0
        do {
            try self.db.transaction {
                var status = ss.status!
                _ = BaseDb.getInstance().userDb?.update(sub: sub)
                var setters = [Setter]()
                setters.append(self.mode <- sub.acs?.serialize())
                setters.append(self.updated <- sub.updated)
                if status != BaseDb.kStatusSynced {
                    setters.append(self.status <- BaseDb.kStatusSynced)
                    status = BaseDb.kStatusSynced
                }
                setters.append(self.read <- sub.getRead)
                setters.append(self.recv <- sub.getRecv)
                setters.append(self.clear <- sub.getClear)
                if let seen = sub.seen {
                    setters.append(self.lastSeen <- seen.when)
                    setters.append(self.userAgent <- seen.ua)
                }
                updated = try self.db.run(record.update(setters))
                ss.status = status
            }
        } catch {
            print("SubscriberDb update failed: \(error)")
            return false
        }
        return updated > 0
    }
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
    func deleteForTopic(topicId: Int64) -> Bool {
        guard let record = self.table?.filter(self.topicId == topicId) else {
            return false
        }
        do {
            return try self.db.run(record.delete()) > 0
        } catch {
            print("delete failed: \(error)")
            return false
        }
    }

    private func readOne(r: Row) -> SubscriptionProto? {
        guard let s = DefaultSubscription.createByName(name: r[self.subscriptionClass]) else { return nil }
        let ss = StoredSubscription()
        ss.id = r[self.id]
        ss.topicId = r[self.topicId]
        ss.userId = r[self.userId]
        ss.status = r[self.status]
        s.acs = Acs.deserialize(from: r[self.mode])
        s.updated = r[self.updated]
        s.read = r[self.read]
        s.recv = r[self.recv]
        s.clear = r[self.clear]
        s.seen = LastSeen(when: r[self.lastSeen], ua: r[self.userAgent])
        //s.user = r[]
        //s.user
        s.payload = ss
        return s
    }

    func readAll(topicId: Int64) -> [SubscriptionProto]? {
        guard let subTable = self.table else {
            return nil
        }
        guard let udb = BaseDb.getInstance().userDb, let udbTable = udb.table else {
            return nil
        }
        guard let tdb = BaseDb.getInstance().topicDb, let tdbTable = tdb.table else {
            return nil
        }
        let joinedTable = subTable.select(
            self.id,
            self.topicId,
            self.userId,
            self.status,
            self.mode,
            self.updated,
            //self.deleted
            self.read,
            self.recv,
            self.clear,
            self.lastSeen,
            self.userAgent,
            self.subscriptionClass)
            .join(.leftOuter, udbTable, on: self.userId == udb.id)
            .join(.leftOuter, tdbTable, on: self.topicId == tdb.id)
            .filter(self.topicId == topicId)

        do {
            var subscriptions = [SubscriptionProto]()
            for row in try db.prepare(joinedTable) {
                if let s = self.readOne(r: row) {
                    subscriptions.append(s)
                } else {
                    print("failed to create subscription for \(row[self.subscriptionClass])")
                }
                
            }
            return subscriptions
        } catch {
            print("failed to read subscriptions \(error)")
            return nil
        }
    }
}
