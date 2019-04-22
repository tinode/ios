//
//  UserDb.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import SQLite
import TinodeSDK

class StoredUser: Payload {
    let id: Int64?
    init(id: Int64) { self.id = id }
}

class UserDb {
    private static let kTableName = "users"
    private let db: SQLite.Connection
    
    public let table: Table
    
    public let id: Expression<Int64>
    public let accountId: Expression<Int64?>
    public let uid: Expression<String?>
    public let updated: Expression<Date?>
    //public let deleted: Expression<Int?>
    public let pub: Expression<String?>
    
    init(_ database: SQLite.Connection) {
        self.db = database
        self.table = Table(UserDb.kTableName)
        self.id = Expression<Int64>("id")
        self.accountId = Expression<Int64?>("account_id")
        self.uid = Expression<String?>("uid")
        self.updated = Expression<Date?>("updated")
        self.pub = Expression<String?>("pub")
    }
    func destroyTable() {
        try! self.db.run(self.table.dropIndex(accountId, uid, ifExists: true))
        try! self.db.run(self.table.drop(ifExists: true))
    }
    func createTable() {
        let accountDb = BaseDb.getInstance().accountDb!
        // Must succeed.
        try! self.db.run(self.table.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(accountId, references: accountDb.table, accountDb.id)
            t.column(uid)
            t.column(updated)
            t.column(pub)
        })
        try! self.db.run(self.table.createIndex(accountId, uid, ifNotExists: true))
    }
    func insert(user: UserProto?) -> Int64 {
        guard let user = user else { return 0 }
        let id = self.insert(uid: user.uid, updated: user.updated, serializedPub: user.serializePub())
        if id > 0 {
            let su = StoredUser(id: id)
            user.payload = su
        }
        return id
    }
    func insert(sub: SubscriptionProto?) -> Int64 {
        guard let sub = sub else { return -1 }
        return self.insert(uid: sub.user, updated: sub.updated, serializedPub: sub.serializePub())
    }
    private func insert(uid: String?, updated: Date?, serializedPub: String?) -> Int64 {
        do {
            let rowid = try db.run(
                self.table.insert(
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
    func update(user: UserProto?) -> Bool {
        guard let user = user, let su = user.payload as? StoredUser, let userId = su.id, userId > 0 else { return false }
        return self.update(userId: userId, updated: user.updated, serializedPub: user.serializePub())
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
        guard setters.count > 0 else { return false }
        let record = self.table.filter(self.id == userId)
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
        if let row = try? db.pluck(self.table.select(self.id).filter(self.uid == uid && self.accountId == accountId)), let r = row?[self.id] {
            return r
        }
        return -1
    }
    func readOne(uid: String?) -> UserProto? {
        guard let uid = uid, let accountId = BaseDb.getInstance().account?.id else {
            return nil
        }
        guard let row = try? db.pluck(self.table.filter(self.uid == uid && self.accountId == accountId)), let r = row else {
            return nil
        }
        let id = r[self.id]
        let updated = r[self.updated]
        let pub = r[self.pub]
        guard let user = DefaultUser.createFromPublicData(uid: uid, updated: updated, data: pub) else { return nil }
        let storedUser = StoredUser(id: id)
        user.payload = storedUser
        return user
    }
}
