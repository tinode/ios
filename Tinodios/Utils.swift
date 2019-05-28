//
//  Utils.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import SwiftKeychainWrapper
import TinodeSDK

class Utils {
    static let kTinodeHasRunBefore = "tinodeHasRunBefore"
    static let kTinodePrefReadReceipts = "tinodePrefSendReadReceipts"
    static let kTinodePrefTypingNotifications = "tinodePrefTypingNoficications"

    public static func getAuthToken() -> String? {
        let userDefaults = UserDefaults.standard
        guard userDefaults.bool(forKey: Utils.kTinodeHasRunBefore) else {
            // Clear the app keychain.
            KeychainWrapper.standard.removeAllKeys()
            userDefaults.set(true, forKey: Utils.kTinodeHasRunBefore)
            return nil
        }
        return KeychainWrapper.standard.string(
            forKey: LoginViewController.kTokenKey)
    }
    public static func registerUserDefaults() {
        /// Here you can give default values to your UserDefault keys
        UserDefaults.standard.register(defaults: [
            Utils.kTinodePrefReadReceipts: true,
            Utils.kTinodePrefTypingNotifications: true
        ])
    }
    // Calculate difference between two arrays of messages. Returns a tuple of insertion indexes and deletion indexes.
    // The indexes are for respective arrays.
    public static func diffMessageArray(old: [Message], new: [Message]) -> (inserted: [Int], removed: [Int]) {
        if old.isEmpty && new.isEmpty {
            return (inserted: [], removed: [])
        }
        if old.isEmpty {
            return (inserted: Array(0 ..< new.count), removed: [])
        }
        if new.isEmpty {
            return (inserted: [], removed: Array(0 ..< old.count))
        }

        var inserted: [Int] = []
        var removed: [Int] = []

        // Match old array against the new array and separate removed items from inserted.
        var o = 0, n = 0
        while o < old.count || n < new.count {
            if o == old.count || (n < new.count && old[o].seqId > new[n].seqId) {
                // Present in new, missing in old: added
                inserted.append(n)
                n += 1

            } else if n == new.count || old[o].seqId < new[n].seqId {
                // Present in old, missing in new: removed
                removed.append(o)
                o += 1

            } else {
                // present in both
                if o < old.count {
                    o += 1
                }
                if n < new.count {
                    n += 1
                }
            }
        }

        print("old: \(old.map({ $0.seqId }))")
        print("new: \(new.map({ $0.seqId }))")

        return (inserted: inserted, removed: removed)
    }

    public static func parseTags(from tagsString: String?) -> [String]? {
        guard let tagsString = tagsString else { return nil }
        let candidates = tagsString.split(separator: ",")
        return candidates.filter { $0.count >= UiUtils.kMinTagLength }.map { String($0) }
    }
}

// Per
// https://medium.com/over-engineering/a-background-repeating-timer-in-swift-412cecfd2ef9
class RepeatingTimer {
    let timeInterval: TimeInterval
    init(timeInterval: TimeInterval) {
        self.timeInterval = timeInterval
    }
    private lazy var timer: DispatchSourceTimer = {
        let t = DispatchSource.makeTimerSource()
        t.schedule(deadline: .now() + self.timeInterval, repeating: self.timeInterval)
        t.setEventHandler(handler: { [weak self] in
            self?.eventHandler?()
        })
        return t
    }()
    var eventHandler: (() -> Void)?
    private enum State {
        case suspended
        case resumed
    }
    private var state: State = .suspended
    deinit {
        timer.setEventHandler {}
        timer.cancel()
        // If the timer is suspended, calling cancel without resuming
        // triggers a crash. This is documented here
        // https://forums.developer.apple.com/thread/15902
        resume()
        eventHandler = nil
    }

    func resume() {
        if state == .resumed {
            return
        }
        state = .resumed
        timer.resume()
    }

    func suspend() {
        if state == .suspended {
            return
        }
        state = .suspended
        timer.suspend()
    }
}
