//
//  BaseDb.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import SQLite

public class BaseDb {
    // Current database schema version. Increment on schema changes.
    public static let kSchemaVersion: Int32 = 100

    // Onject statuses.
    // Status undefined/not set.
    public static let kStatusUndefined = 0
    // Object is not ready to be sent to the server.
    public static let kStatusDraft = 1
    // Object is ready but not yet sent to the server.
    public static let kStatusQueued = 2
    // Object is in the process of being sent to the server.
    public static let kStatusSending = 3
    // Object is received by the server.
    public static let kStatusSynced = 4
    // Meta-status: object should be visible in the UI.
    public static let kStatusVisible = 4
    // Object is hard-deleted.
    public static let kStatusDeletedHard = 5
    // Object is soft-deleted.
    public static let kStatusDeletedSoft = 6
    // Object is rejected by the server.
    public static let kStatusRejected = 7

    public static var `default`: BaseDb? = nil
    private let kDatabaseName = "basedb.sqlite3"
    var db: SQLite.Connection?
    private let pathToDatabase: String
    var sqlStore: SqlStore?
    var topicDb: TopicDb? = nil
    var accountDb: AccountDb? = nil
    var subscriberDb: SubscriberDb? = nil
    var userDb: UserDb? = nil
    var messageDb: MessageDb? = nil
    var account: StoredAccount? = nil
    var isReady: Bool { get { return self.account != nil } }
    init() {
        var documentsDirectory = (NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString) as String
        if documentsDirectory.last! != "/" {
            documentsDirectory.append("/")
        }
        self.pathToDatabase = documentsDirectory.appending("database.sqlite")

        do {
            self.db = try SQLite.Connection(self.pathToDatabase)
        } catch {
            print(error.localizedDescription)
        }
        assert(self.db != nil)

        self.sqlStore = SqlStore(dbh: self)
    }
    private func initDb() {
        self.accountDb = AccountDb(self.db!)
        self.userDb = UserDb(self.db!, baseDb: self)
        self.topicDb = TopicDb(self.db!, baseDb: self)
        self.subscriberDb = SubscriberDb(self.db!, baseDb: self)
        self.messageDb = MessageDb(self.db!, baseDb: self)

        if self.db!.schemaVersion != BaseDb.kSchemaVersion {
            print("Schema has changed from \(self.db?.schemaVersion ?? -1) to \(BaseDb.kSchemaVersion)")
            // Delete database if schema has changed.
            self.dropDb()

            self.db!.schemaVersion = BaseDb.kSchemaVersion
        }

        self.accountDb!.createTable()
        self.userDb!.createTable()
        self.topicDb!.createTable()
        self.subscriberDb!.createTable()
        self.messageDb!.createTable()

        self.account = self.accountDb!.getActiveAccount()
    }
    private func dropDb() {
        self.messageDb?.destroyTable()
        self.subscriberDb?.destroyTable()
        self.topicDb?.destroyTable()
        self.userDb?.destroyTable()
        self.accountDb?.destroyTable()
    }
    static func getInstance() -> BaseDb {
        if let instance = BaseDb.default {
            return instance
        }
        let instance = BaseDb()
        BaseDb.default = instance
        instance.initDb()
        return instance
    }
    func isMe(uid: String?) -> Bool {
        guard let uid = uid, let acctUid = BaseDb.getInstance().uid else { return false }
        return uid == acctUid
    }
    var uid: String? {
        get { return self.account?.uid }
    }
    func setUid(uid: String?) {
        guard let uid = uid else {
            self.account = nil
            return
        }
        do {
            if self.account != nil {
                try self.accountDb?.deactivateAll()
            }
            self.account = self.accountDb?.addOrActivateAccount(for: uid)
        } catch {
            print("setUid failed \(error)")
            self.account = nil
        }
    }
    func logout() {
        _ = try? self.accountDb?.deactivateAll()
        self.setUid(uid: nil)
    }
    public static func updateCounter(db: SQLite.Connection, table: Table,
                                     usingIdColumn idColumn: Expression<Int64>, forId id: Int64,
                                     in column: Expression<Int?>, with value: Int) -> Bool {
        let record = table.filter(idColumn == id && column < value)
        do {
            return try db.run(record.update(column <- value)) > 0
        } catch {
            print("updateCounter failed: \(error)")
            return false
        }
    }
}

// Database schema versioning.
extension Connection {
    public var schemaVersion: Int32 {
        get { return Int32((try? scalar("PRAGMA user_version") as! Int64) ?? -1) }
        set { try! run("PRAGMA user_version = \(newValue)") }
    }
}
