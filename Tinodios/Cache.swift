//
//  Cache.swift
//  Tinodios
//
//  Copyright © 2019-2022 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB
import Firebase

class Cache {
    private static let shared = Cache()

    private var mediaRecorderInstance: MediaRecorder?
    private var tinodeInstance: Tinode?
    private var timer = RepeatingTimer(timeInterval: 60 * 60 * 4) // Once every 4 hours.
    private var largeFileHelper: LargeFileHelper?
    private var queue = DispatchQueue(label: "co.tinode.cache")
    internal static let log = TinodeSDK.Log(subsystem: "co.tinode.tinodios")

    // Video call handling.
    public static var callManager = CallManager()

    public static var tinode: Tinode {
        return Cache.shared.getTinode()
    }
    public static func getLargeFileHelper(withIdentifier identifier: String? = nil) -> LargeFileHelper {
        return Cache.shared.getLargeFileHelper(withIdentifier: identifier)
    }
    public static func invalidate() {
        if let tinode = Cache.shared.tinodeInstance {
            Cache.shared.timer.suspend()
            tinode.remoteAllListeners()
            tinode.logout()
            Messaging.messaging().deleteToken { error in
                Cache.log.debug("Failed to delete FCM token: %@", error.debugDescription)
            }
            Cache.shared.tinodeInstance = nil
        }
    }
    public static func isContactSynchronizerActive() -> Bool {
        return Cache.shared.timer.state == .resumed
    }
    public static func synchronizeContactsPeriodically() {
        Cache.shared.timer.suspend()
        // Try to synchronize contacts immediately
        ContactsSynchronizer.default.run()
        // And repeat once every 4 hours.
        Cache.shared.timer.eventHandler = { ContactsSynchronizer.default.run() }
        Cache.shared.timer.resume()
    }
    private func getTinode() -> Tinode {
        // TODO: fix tsan false positive.
        // TSAN fires because one thread may read |tinode| variable
        // while another thread may be writing it below in the critical section.
        if tinodeInstance == nil {
            queue.sync {
                if tinodeInstance == nil {
                    tinodeInstance = SharedUtils.createTinode()
                    DispatchQueue.main.async {
                        self.tinodeInstance?.addListener((UIApplication.shared.delegate as! AppDelegate).callListener)
                    }
                    // Tell contacts synchronizer to attempt to synchronize contacts.
                    ContactsSynchronizer.default.appBecameActive()
                }
            }
        }
        return tinodeInstance!
    }

    private func getLargeFileHelper(withIdentifier identifier: String?) -> LargeFileHelper {
        if largeFileHelper == nil {
            let id = identifier ?? "tinode-\(Date().millisecondsSince1970)"
            let config = URLSessionConfiguration.background(withIdentifier: id)
            largeFileHelper = LargeFileHelper(with: Cache.tinode, config: config)
        }
        return largeFileHelper!
    }

    public static func totalUnreadCount() -> Int {
        guard let topics = tinode.getTopics() else {
            return 0
        }
        return topics.reduce(into: 0, { result, topic in
            result += topic.isReader && !topic.isMuted ? topic.unread : 0
        })
    }

    private func initMediaRecorder() -> MediaRecorder {
        mediaRecorderInstance = MediaRecorder()
        mediaRecorderInstance!.maxDuration = 600_000 // 10 min
        return mediaRecorderInstance!
    }

    public static var mediaRecorder: MediaRecorder {
        if let recorder = Cache.shared.mediaRecorderInstance {
            return recorder
        }
        return Cache.shared.initMediaRecorder()
    }
}
