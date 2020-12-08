//
//  BaseDb.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import SQLite
import TinodeSDK

public class BaseDb {
    // Current database schema version. Increment on schema changes.
    public static let kSchemaVersion: Int32 = 106

    // Object statuses. Values are incremented by 10 to make it easier to add new statuses.
    public enum Status: Int, Comparable {
        // Status undefined/not set.
        case undefined = 0
        // Object is not ready to be sent to the server.
        case draft = 10
        // Object is ready but not yet sent to the server.
        case queued = 20
        // Object is in the process of being sent to the server.
        case sending = 30
        // Sending failed
        case failed = 40
        // Object is received by the server.
        case synced = 50
        // Object is hard-deleted.
        case deletedHard = 60
        // Object is soft-deleted.
        case deletedSoft = 70
        // Object is a deletion range marker synchronized with the server.
        case deletedSynced = 80

        public static func < (lhs: BaseDb.Status, rhs: BaseDb.Status) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    // Meta-status: object should be visible in the UI.
    public static let kStatusVisible = Status.synced

    public static let kBundleId = "co.tinode.tinodios.db"
    public static let kAppGroupId = "group." + BaseDb.kBundleId
    // No direct access to the shared instance.
    private static var `default`: BaseDb? = nil
    private static let accessQueue = DispatchQueue(label: BaseDb.kBundleId)
    private let kDatabaseName = "basedb.sqlite3"
    var db: SQLite.Connection?
    private let pathToDatabase: String
    public var sqlStore: SqlStore?
    public var topicDb: TopicDb? = nil
    public var accountDb: AccountDb? = nil
    public var subscriberDb: SubscriberDb? = nil
    public var userDb: UserDb? = nil
    public var messageDb: MessageDb? = nil
    var account: StoredAccount? = nil
    var isCredValidationRequired: Bool {
        return !(self.account?.credMethods?.isEmpty ?? true)
    }
    public var isReady: Bool {
        return self.account != nil && !self.isCredValidationRequired
    }

    internal static let log = TinodeSDK.Log(subsystem: BaseDb.kBundleId)

    /// The init is private to ensure that the class is a singleton.
    private init() {
        var documentsDirectory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: BaseDb.kAppGroupId)!.absoluteString
        if documentsDirectory.last! != "/" {
            documentsDirectory.append("/")
        }
        self.pathToDatabase = documentsDirectory.appending("database.sqlite")

        do {
            self.db = try SQLite.Connection(self.pathToDatabase)
        } catch {
            BaseDb.log.error("BaseDb - init failed: %@", error.localizedDescription)
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
            BaseDb.log.info("BaseDb - schema has changed from %d to %d",
                            (self.db?.schemaVersion ?? -1), BaseDb.kSchemaVersion)
            // Delete database if schema has changed.
            self.dropDb()

            self.db!.schemaVersion = BaseDb.kSchemaVersion
        }

        self.accountDb!.createTable()
        self.userDb!.createTable()
        self.topicDb!.createTable()
        self.subscriberDb!.createTable()
        self.messageDb!.createTable()
        // Enable foreign key enforcement.
        try! self.db!.run("PRAGMA foreign_keys = ON")

        self.account = self.accountDb!.getActiveAccount()
    }
    private func dropDb() {
        self.messageDb?.destroyTable()
        self.subscriberDb?.destroyTable()
        self.topicDb?.destroyTable()
        self.userDb?.destroyTable()
        self.accountDb?.destroyTable()
    }
    public static var sharedInstance: BaseDb {
        return BaseDb.accessQueue.sync {
            if let instance = BaseDb.default {
                return instance
            }
            let instance = BaseDb()
            BaseDb.default = instance
            instance.initDb()
            return instance
        }
    }
    func isMe(uid: String?) -> Bool {
        guard let uid = uid, let acctUid = BaseDb.sharedInstance.uid else { return false }
        return uid == acctUid
    }
    var uid: String? {
        return self.account?.uid
    }
    func setUid(uid: String?, credMethods: [String]?) {
        guard let uid = uid else {
            self.account = nil
            return
        }
        do {
            if self.account != nil {
                try self.accountDb?.deactivateAll()
            }
            self.account = self.accountDb?.addOrActivateAccount(for: uid, withCredMethods: credMethods)
        } catch {
            BaseDb.log.error("BaseDb - setUid failed %@", error.localizedDescription)
            self.account = nil
        }
    }
    public func logout() {
        _ = try? self.accountDb?.deactivateAll()
        self.setUid(uid: nil, credMethods: nil)
    }

    public func deleteUid(_ uid: String) -> Bool {
        var acc: StoredAccount?
        if self.uid == uid {
            acc = self.account
            self.account = nil
        } else {
            acc = self.accountDb?.getByUid(uid: uid)
        }
        guard let acc2 = acc else {
            BaseDb.log.error("Could not find account for uid [%@]", uid)
            return false
        }
        do {
            try self.db?.savepoint("BaseDb.deleteUid") {
                if !(self.topicDb?.deleteAll(forAccount: acc2.id) ?? true) {
                    BaseDb.log.error("Failed to clear topics/messages/subscribers for account id [%lld]", acc2.id)
                }
                if !(self.userDb?.delete(forAccount: acc2.id) ?? true) {
                    BaseDb.log.error("Failed to clear users for account id [%lld]", acc2.id)
                }
                if !(self.accountDb?.delete(accountId: acc2.id) ?? true) {
                    BaseDb.log.error("Failed to delete account for id [%lld]", acc2.id)
                }
            }
        } catch {
            BaseDb.log.error("BaseDb - deleteUid operation failed: uid = %@, error = %@", uid, error.localizedDescription)
            return false
        }
        return true
    }

    public static func updateCounter(db: SQLite.Connection, table: Table,
                                     usingIdColumn idColumn: Expression<Int64>, forId id: Int64,
                                     in column: Expression<Int?>, with value: Int) -> Bool {
        let record = table.filter(idColumn == id && column < value)
        do {
            return try db.run(record.update(column <- value)) > 0
        } catch {
            BaseDb.log.error("BaseDb - updateCounter failed %@", error.localizedDescription)
            return false
        }
    }
}

// Database schema versioning.
extension SQLite.Connection {
    public var schemaVersion: Int32 {
        get { return Int32((try? scalar("PRAGMA user_version") as? Int64) ?? -1) }
        set { try! run("PRAGMA user_version = \(newValue)") }
    }
}
