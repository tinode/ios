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
    public static let kSchemaVersion: Int32 = 104

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
    // Object is a deletion range marker synchronized with the server.
    public static let kStatusDeletedSynced = 7

    public static let kBundleId = "co.tinode.tinodios.db"
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
        get { return !(self.account?.credMethods?.isEmpty ?? true) }
    }
    public var isReady: Bool { get { return self.account != nil && !self.isCredValidationRequired } }

    internal static let log = TinodeSDK.Log(subsystem: BaseDb.kBundleId)

    /// The init is private to ensure that the class is a singleton.
    private init() {
        var documentsDirectory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group." + BaseDb.kBundleId)!.absoluteString
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
    public static func getInstance() -> BaseDb {
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
        guard let uid = uid, let acctUid = BaseDb.getInstance().uid else { return false }
        return uid == acctUid
    }
    var uid: String? {
        get { return self.account?.uid }
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
        get { return Int32((try? scalar("PRAGMA user_version") as! Int64) ?? -1) }
        set { try! run("PRAGMA user_version = \(newValue)") }
    }
}
