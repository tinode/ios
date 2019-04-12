//
//  BaseDb.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import SQLite

public class BaseDb {
    // Status undefined/not set.
    public static let kStatusUndefined = 0
    // Object is not ready to be sent to the server.
    public static let kStatusDraft = 1
    // Object is ready but not yet sent to the server
    public static let kStatusQueued = 2
    // Object is received by the server
    public static let kStatusSynced = 3
    // Meta-status: object should be visible in the UI
    public static let kStatusVisible = 3
    // Object is hard-deleted
    public static let kStatusDeletedHard = 4
    // Object is soft-deleted
    public static let kStatusDeletedSoft = 5
    // Object is rejected by the server.
    public static let kStatusRejected = 6

    
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
    deinit{
        self.onDestroy()
    }
    private func onCreate() {
        self.accountDb = AccountDb(self.db!)
        self.accountDb!.createTable()
        self.userDb = UserDb(self.db!)
        self.userDb!.createTable()
        self.topicDb = TopicDb(self.db!)
        self.topicDb!.createTable()
        self.subscriberDb = SubscriberDb(self.db!)
        self.subscriberDb!.createTable()
        self.messageDb = MessageDb(self.db!)
        self.messageDb!.createTable()
        self.account = self.accountDb!.getActiveAccount()
    }
    private func onDestroy() {
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
        instance.onCreate()
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
}
