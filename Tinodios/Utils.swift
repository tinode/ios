//
//  Utils.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import SwiftKeychainWrapper

class Utils {
    static let kTinodeHasRunBefore = "tinodeHasRunBefore"

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
