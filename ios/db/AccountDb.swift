//
//  AccountDb.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import SQLite

public class StoredAccount {
    var id: Int64
    let uid: String
    init(id: Int64, uid: String) {
        self.id = id
        self.uid = uid
    }
}

public class AccountDb {
    private static let kTableName = "accounts"
    private let db: SQLite.Connection
    
    public var table: Table? = nil
    
    public let id: Expression<Int64>
    public let uid: Expression<String?>
    public let active: Expression<Int?>
    public let deviceId: Expression<String?>
    
    init(_ database: SQLite.Connection) {
        self.db = database
        self.id = Expression<Int64>("id")
        self.uid = Expression<String?>("uid")
        self.active = Expression<Int?>("last_active")
        self.deviceId = Expression<String?>("device_id")
    }
    func destroyTable() {
        try! self.db.run(self.table!.dropIndex(uid))
        try! self.db.run(self.table!.dropIndex(active))
        try! self.db.run(self.table!.drop(ifExists: true))
    }
    func createTable() {
        self.table = Table(AccountDb.kTableName)
        // Must succeed.
        try! self.db.run(self.table!.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(uid)
            t.column(active)
            t.column(deviceId)
        })
        try! self.db.run(self.table!.createIndex(uid, unique: true, ifNotExists: true))
        try! self.db.run(self.table!.createIndex(active, ifNotExists: true))
    }
    @discardableResult
    func deactivateAll() throws -> Int {
        return try self.db.run(self.table!.update(self.active <- 0))
    }
    private func getByUid(uid: String) -> Int64 {
        if let row = try? db.pluck(self.table!.select(self.id).filter(self.uid == uid)), let r = row?[self.id] {
            return r
        }
        return -1
    }
    func addOrActivateAccount(for uid: String) -> StoredAccount? {
        var result: StoredAccount? = nil
        do {
            try db.savepoint("AccountDb.addOrActivateAccount") {
                try self.deactivateAll()
                result = StoredAccount(id: self.getByUid(uid: uid), uid: uid)
                if result!.id >= 0 {
                    let record = self.table!.filter(self.id == result!.id)
                    try db.run(record.update(self.active <- 1))
                } else {
                    result!.id = try db.run(self.table!.insert(
                        self.uid <- uid,
                        self.active <- 1))
                }
                if result!.id < 0 {
                    result = nil
                }
            }
        } catch {
            result = nil
        }
        return result
    }
    func getActiveAccount() -> StoredAccount? {
        if let row = try? db.pluck(self.table!.select(self.id, self.uid).filter(self.active == 1)),
            let rid = row?[self.id], let ruid = row?[self.uid] {
            return StoredAccount(id: rid, uid: ruid)
        }
        return nil
    }
    func updateDeviceToken(token: String) -> Bool {
        let record = self.table!.filter(self.active == 1)
        do {
            return try self.db.run(record.update(self.deviceId <- token)) > 0
        } catch {
            return false
        }
    }
    func getDeviceToken() -> String? {
        if let row = try? db.pluck(self.table!.select(self.deviceId).filter(self.active == 1)),
            let d = row?[self.deviceId] {
            return d
        }
        return nil
    }
}
