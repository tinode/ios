//
//  BaseDb.swift
//  msgr
//
//  Copyright © 2018 msgr. All rights reserved.
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

    
    public static var `default` = BaseDb()
    private let kDatabaseName = "basedb.sqlite3"
    private var db: SQLite.Connection?
    private let pathToDatabase: String
    var sqlStore: SqlStore?
    var topicDb: TopicDb? = nil
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
        sqlStore = SqlStore(dbh: self)
    }
    deinit{
        self.onDestroy()
    }
    private func onCreate() {
        self.topicDb = TopicDb(self.db!)
        self.topicDb?.createTable()
    }
    private func onDestroy() {
        self.topicDb?.destroyTable()
    }
    static func getInstance() -> BaseDb {
        let instance = BaseDb.default
        instance.onCreate()
        return instance
    }
}
