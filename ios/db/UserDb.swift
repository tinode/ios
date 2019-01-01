//
//  UserDb.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import SQLite

class UserDb {
    private static let kTableName = "users"
    private let db: SQLite.Connection
    
    private var table: Table? = nil
    
    private let id: Expression<Int64>
    private let accountId: Expression<Int64?>
    private let uid: Expression<String?>
    private let updated: Expression<Date?>
    //private let deleted: Expression<Int?>
    private let pub: Expression<String?>
    
    init(_ database: SQLite.Connection) {
        self.db = database
        self.id = Expression<Int64>("id")
        self.accountId = Expression<Int64?>("account_id")
        self.uid = Expression<String?>("uid")
        self.updated = Expression<Date?>("updated")
        self.pub = Expression<String?>("pub")
    }
    func destroyTable() {
        //try! self.db.run(self.table!.dropIndex(topicId))
        try! self.db.run(self.table!.drop(ifExists: true))
    }
    func createTable() {
        self.table = Table(UserDb.kTableName)
        // Must succeed.
        try! self.db.run(self.table!.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(accountId)
            t.column(uid)
            t.column(updated)
            t.column(pub)
        })
        //try! self.db.run(self.table!.createIndex(topicId, ifNotExists: true))
    }
    func insert(sub: SubscriptionProto?) -> Int64 {
        guard let sub = sub else { return -1 }
        return self.insert(uid: sub.user, updated: sub.updated, serializedPub: sub.serializePub())
    }
    private func insert(uid: String?, updated: Date?, serializedPub: String?) -> Int64 {
        do {
            let rowid = try db.run(
                self.table!.insert(
                    //email <- "alice@mac.com"
                    //accountId <- ,
                    self.accountId <- BaseDb.getInstance().account?.id,
                    self.uid <- uid,
                    self.updated <- updated ?? Date(),
                    self.pub <- serializedPub//Tinode.serializeObject(t: pub)
            ))
            return rowid
        } catch {
            print("UserDb insertion failed: \(error)")
            return -1
        }
    }
    func update(sub: SubscriptionProto?) -> Bool {
        guard let st = sub?.payload as? StoredSubscription, let userId = st.userId else { return false }
        return self.update(userId: userId, updated: sub?.updated, serializedPub: sub?.serializePub())
    }
    private func update(userId: Int64, updated: Date?, serializedPub: String?) -> Bool {
        var setters = [Setter]()
        if let u = updated {
            setters.append(self.updated <- u)
        }
        if let s = serializedPub {
            setters.append(self.pub <- s)
        }
        guard setters.count > 0, let record = self.table?.filter(self.id == userId) else {
            return false
        }
        do {
            return try self.db.run(record.update(setters)) > 0
        } catch {
            print("UserDb update failed: \(error)")
            return false
        }
    }
    func getId(for uid: String?) -> Int64 {
        guard let accountId = BaseDb.getInstance().account?.id else  {
            return -1
        }
        if let row = try? db.pluck(self.table!.select(self.id).filter(self.uid == uid && self.accountId == accountId)), let r = row?[self.id] {
            return r
        }
        return -1
    }
}
