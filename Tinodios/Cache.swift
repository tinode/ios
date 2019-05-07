//
//  Cache.swift
//  Tinodios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

class Cache {
    private static let `default` = Cache()

    public static let kHostName = "ws://127.0.0.1:6060" // localhost

    private static let kApiKey = "AQEAAAABAAD_rAp4DJh05a1HAwFT3A6K"

    var tinode: Tinode? = nil

    static func getTinode() -> Tinode {
        return Cache.default.getTinode()
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
