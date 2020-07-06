//
//  AccountDb.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import SQLite

public class StoredAccount {
    var id: Int64
    let uid: String
    var credMethods: [String]?
    init(id: Int64, uid: String, credMethods: [String]?) {
        self.id = id
        self.uid = uid
        self.credMethods = credMethods
    }
}

public class AccountDb {
    public static let kTableName = "accounts"
    private let db: SQLite.Connection

    public var table: Table

    public let id: Expression<Int64>
    public let uid: Expression<String?>
    public let active: Expression<Int?>
    public let credMethods: Expression<String?>
    public let deviceId: Expression<String?>

    init(_ database: SQLite.Connection) {
        self.db = database
        self.table = Table(AccountDb.kTableName)
        self.id = Expression<Int64>("id")
        self.uid = Expression<String?>("uid")
        self.active = Expression<Int?>("last_active")
        self.credMethods = Expression<String?>("cred_methods")
        self.deviceId = Expression<String?>("device_id")
    }
    func destroyTable() {
        try! self.db.run(self.table.dropIndex(uid, ifExists: true))
        try! self.db.run(self.table.dropIndex(active, ifExists: true))
        try! self.db.run(self.table.drop(ifExists: true))
    }
    func createTable() {
        // Must succeed.
        try! self.db.run(self.table.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(uid)
            t.column(active)
            t.column(credMethods)
            t.column(deviceId)
        })
        try! self.db.run(self.table.createIndex(uid, unique: true, ifNotExists: true))
        try! self.db.run(self.table.createIndex(active, ifNotExists: true))
    }
    @discardableResult
    func deactivateAll() throws -> Int {
        return try self.db.run(self.table.update(self.active <- 0))
    }
    public func getByUid(uid: String) -> StoredAccount? {
        if let row = try? db.pluck(self.table.select(self.id, self.credMethods).filter(self.uid == uid)) {
            return StoredAccount(id: row[self.id], uid: uid, credMethods: row[self.credMethods]?.components(separatedBy: ","))
        }
        return nil
    }
    func addOrActivateAccount(for uid: String, withCredMethods meth: [String]?) -> StoredAccount? {
        var result: StoredAccount? = nil
        do {
            try db.savepoint("AccountDb.addOrActivateAccount") {
                try self.deactivateAll()
                result = self.getByUid(uid: uid)
                let serializedCredMeth = meth?.joined(separator: ",")
                if result != nil {
                    let record = self.table.filter(self.id == result!.id)
                    try db.run(record.update(
                        self.active <- 1,
                        self.credMethods <- serializedCredMeth))
                } else {
                    let newId = try db.run(self.table.insert(
                        self.uid <- uid,
                        self.active <- 1,
                        self.credMethods <- serializedCredMeth))
                    result = StoredAccount(id: newId, uid: uid, credMethods: meth)
                }
                if result!.id < 0 {
                    result = nil
                } else {
                    result?.credMethods = meth
                }
            }
        } catch {
            BaseDb.log.debug("failed to add account '%@'", error.localizedDescription)
            result = nil
        }
        return result
    }

    func delete(accountId: Int64) -> Bool {
        let record = self.table.filter(self.id == accountId)
        do {
            return try self.db.run(record.delete()) > 0
        } catch {
            BaseDb.log.error("AccountDb - delete(accountId) operation failed: accountId = %lld, error = %@", accountId, error.localizedDescription)
            return false
        }
    }

    func getActiveAccount() -> StoredAccount? {
        if let row = try? db.pluck(self.table.select(self.id, self.uid, self.credMethods).filter(self.active == 1)),
            let ruid = row[self.uid] {
            return StoredAccount(id: row[self.id], uid: ruid, credMethods: row[self.credMethods]?.components(separatedBy: ","))
        }
        return nil
    }
    @discardableResult
    func saveDeviceToken(token: String?) -> Bool {
        let record = self.table.filter(self.active == 1)
        do {
            return try self.db.run(record.update(self.deviceId <- token)) > 0
        } catch {
            return false
        }
    }
    func getDeviceToken() -> String? {
        if let row = try? db.pluck(self.table.select(self.deviceId).filter(self.active == 1)),
            let d = row[self.deviceId] {
            return d
        }
        return nil
    }
}
