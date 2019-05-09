//
//  Cache.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import UIKit
import TinodeSDK

class Cache {
    private static let `default` = Cache()

    public static let kHostName = "ws://127.0.0.1:6060" // localhost

    private static let kApiKey = "AQEAAAABAAD_rAp4DJh05a1HAwFT3A6K"

    private var tinode: Tinode? = nil
    private var timer = RepeatingTimer(timeInterval: 60 * 60 * 4) // Once every 4 hours.

    public static func getTinode() -> Tinode {
        return Cache.default.getTinode()
    }
    public static func synchronizeContactsPeriodically() {
        Cache.default.timer.suspend()
        // Try to synchronize contacts immediately
        ContactsSynchronizer.default.run()
        // And repeat once every 4 hours.
        Cache.default.timer.eventHandler = { ContactsSynchronizer.default.run() }
        Cache.default.timer.resume()
    }
    private func getTinode() -> Tinode {
        if tinode == nil {
            let appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
            let appName = "Tinodios/" + appVersion
            let dbh = BaseDb.getInstance()
            tinode = Tinode(for: appName,
                            authenticateWith: Cache.kApiKey,
                            persistDataIn: dbh.sqlStore)
            tinode!.OsVersion = UIDevice.current.systemVersion
            // FIXME: this should be FCM or APNS push ID
            tinode!.deviceId = UIDevice.current.identifierForVendor!.uuidString
        }
        return tinode!
    }
}
