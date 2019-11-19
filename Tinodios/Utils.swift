//
//  Utils.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import MobileCoreServices
import SwiftKeychainWrapper
import TinodeSDK
import TinodiosDB

class Utils {
    static let kTinodeHasRunBefore = "tinodeHasRunBefore"
    static let kTinodePrefReadReceipts = "tinodePrefSendReadReceipts"
    static let kTinodePrefTypingNotifications = "tinodePrefTypingNoficications"
    static let kTinodePrefLastLogin = "tinodeLastLogin"

    public static func getSavedLoginUserName() -> String? {
        return UserDefaults.standard.string(forKey: Utils.kTinodePrefLastLogin)
    }

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

    public static func removeAuthToken() {
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: Utils.kTinodePrefLastLogin)
        KeychainWrapper.standard.removeAllKeys()
    }

    public static func saveAuthToken(for userName: String, token: String?) {
        UserDefaults.standard.set(userName, forKey: Utils.kTinodePrefLastLogin)
        if let token = token, !token.isEmpty {
            let tokenSaveSuccessful = KeychainWrapper.standard.set(
                token, forKey: LoginViewController.kTokenKey)
            if !tokenSaveSuccessful {
                Cache.log.error("Could not save auth token")
            }
        }
    }

    public static func registerUserDefaults() {
        /// Here you can give default values to your UserDefault keys
        UserDefaults.standard.register(defaults: [
            Utils.kTinodePrefReadReceipts: true,
            Utils.kTinodePrefTypingNotifications: true
        ])

        let (hostName, _, _) = SettingsHelper.getConnectionSettings()
        if hostName == nil {
            // If hostname is nil, sync values to defaults
            SettingsHelper.setHostName(Bundle.main.object(forInfoDictionaryKey: "HOST_NAME") as? String)
            SettingsHelper.setUseTLS(Bundle.main.object(forInfoDictionaryKey: "USE_TLS") as? String)
        }
    }

    // Calculate difference between two arrays of messages. Returns a tuple of insertion indexes and deletion indexes.
    // First the deletion indexes are applied to the old array. Then insertions are applied to the remaining array.
    // Indexes should be applied in descending order.
    public static func diffMessageArray(sortedOld old: [Message], sortedNew new: [Message]) -> (removed: [Int], inserted: [Int], mutated: [Int]) {
        if old.isEmpty && new.isEmpty {
            return (inserted: [], removed: [], mutated: [])
        }
        if old.isEmpty {
            return (inserted: Array(0 ..< new.count), removed: [], mutated: Array(0 ..< new.count))
        }
        if new.isEmpty {
            return (inserted: [], removed: Array(0 ..< old.count), mutated: [])
        }

        var inserted: [Int] = []
        var removed: [Int] = []
        var mutated: [Int] = []

        // Match old array against the new array to separate removed items from inserted.
        var o = 0, n = 0
        while o < old.count || n < new.count {
            if o == old.count || (n < new.count && old[o].seqId > new[n].seqId) {
                // Present in new, missing in old: added
                inserted.append(n)
                if mutated.last ?? -1 != n {
                    mutated.append(n)
                }
                n += 1

            } else if n == new.count || old[o].seqId < new[n].seqId {
                // Present in old, missing in new: removed
                removed.append(o)
                if mutated.last ?? -1 != n && n < new.count {
                    // Appending n, not o because mutated is an index agaist the new data.
                    mutated.append(n)
                }
                o += 1

            } else {
                // present in both
                if o < old.count && n < new.count && !old[o].equals(new[n]) {
                    mutated.append(n)
                }
                if o < old.count {
                    o += 1
                }
                if n < new.count {
                    n += 1
                }
            }
        }

        return (inserted: inserted, removed: removed, mutated: mutated)
    }

    public static func isValidTag(tag: String) -> Bool {
        return tag.count >= UiUtils.kMinTagLength
    }

    public static func uniqueFilename(forMime mime: String?) -> String {
        let mimeType: CFString = (mime ?? "application/octet-stream") as CFString
        var ext: String? = nil
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType, nil)?.takeUnretainedValue() {
            ext = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassFilenameExtension)?.takeUnretainedValue() as String?
        }
        return ProcessInfo.processInfo.globallyUniqueString + "." + (ext ?? "bin")
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
    public enum State {
        case suspended
        case resumed
    }
    public var state: State = .suspended
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

class RelativeDateFormatter {
    // DateFormatter is thread safe, OK to keep a copy.
    static let shared = RelativeDateFormatter()

    private let formatter = DateFormatter()

    func dateOnly(from date: Date?, style: DateFormatter.Style = .medium) -> String {
        guard let date = date else { return "Never ??:??" }

        formatter.timeStyle = .none
        formatter.dateStyle = style
        switch true {
        case Calendar.current.isDateInToday(date) || Calendar.current.isDateInYesterday(date):
            // "today", "yesterday"
            formatter.doesRelativeDateFormatting = true
        case Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear):
            // day of the week "Wednesday", "Friday" etc
            formatter.dateFormat = "EEEE"
        default:
            // All other dates: "Mar 15, 2019"
            break
        }
        return formatter.string(from: date)
    }

    func timeOnly(from date: Date?, style: DateFormatter.Style = .short) -> String {
        guard let date = date else { return "??:??" }

        formatter.timeStyle = style
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    // Incrementally longer formatting of a date.
    func shortDate(from date: Date?) -> String {
        guard let date = date else { return "Never ??:??" }

        let now = Date()
        if Calendar.current.isDate(date, equalTo: now, toGranularity: .year) {
            if Calendar.current.isDate(date, equalTo: now, toGranularity: .day) {
                formatter.timeStyle = .short
                formatter.dateStyle = .none
                return formatter.string(from: date)
            } else {
                formatter.timeStyle = .short
                formatter.dateStyle = .short
                return formatter.string(from: date)
            }
        }

        formatter.timeStyle = .medium
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

extension URL {
    public func extractQueryParam(withName name: String) -> String? {
        let components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == name })?.value
    }
}

extension Tinode {
    func connectDefault() throws -> PromisedReply<ServerMessage>? {
        let (hostName, useTLS, _) = SettingsHelper.getConnectionSettings()
        Cache.log.debug("Connecting to %@, secure %@", hostName ?? Cache.kHostName, useTLS ?? Cache.kUseTLS ? "YES" : "NO")
        return try connect(to: (hostName ?? Cache.kHostName), useTLS: (useTLS ?? Cache.kUseTLS))
    }
}

extension StoredMessage {
    /// Generate and cache NSAttributedString representation of Drafty content.
    func attributedContent(fitIn size: CGSize, withDefaultAttributes attributes: [NSAttributedString.Key : Any]? = nil) -> NSAttributedString? {
        if cachedContent != nil {
            return cachedContent
        }
        guard let content = content else { return nil }
        cachedContent = AttributedStringFormatter.toAttributed(content, fitIn: size, withDefaultAttributes: attributes)
        return cachedContent
    }

    // Returns true if message contains an inline image.
    var isImage: Bool {
        guard let entity = self.content?.entities?[0] else { return false }
        return entity.data?["val"] != nil && entity.data?["mime"] != nil
    }
}
