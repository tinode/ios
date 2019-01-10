//
//  Cache.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import UIKit

class Cache {
    private static let `default` = Cache()

    public static let kHostName = "127.0.0.1:6060" // local host
    
    private static let kApiKey = "AQEAAAABAAD_rAp4DJh05a1HAwFT3A6K"
    
    var tinode: Tinode? = nil
    
    static func getTinode() -> Tinode {
        return Cache.default.getTinode()
    }
    private func getTinode() -> Tinode {
        if tinode == nil {
            let appName = "Tinode-iOS/" + UIDevice.current.systemVersion
            // TODO: uncomment when the transaction issue is resolved.
            // let dbh = BaseDb.getInstance()
            tinode = Tinode(for: appName,
                            authenticateWith: Cache.kApiKey,
                            persistDataIn: nil)
                            //persistDataIn: dbh.sqlStore)
            tinode!.deviceId = UIDevice.current.identifierForVendor!.uuidString
        }
        return tinode!
    }
}
