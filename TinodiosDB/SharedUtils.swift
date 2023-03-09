//
//  SharedUtils.swift
//  TinodiosDB
//
//  Copyright © 2020-2022 Tinode. All rights reserved.
//

import Foundation
import SwiftKeychainWrapper
import TinodeSDK

public class SharedUtils {
    static public let kNotificationBrandingSmallIconAvailable = "BrandingSmallIconAvailable"
    static public let kNotificationBrandingConfigAvailable = "BrandingConfigAvailable"

    static public let kTinodeMetaVersion = "tinodeMetaVersion"

    static public let kTinodePrefLastLogin = "tinodeLastLogin"
    static public let kTinodePrefReadReceipts = "tinodePrefSendReadReceipts"
    static public let kTinodePrefTypingNotifications = "tinodePrefTypingNoficications"
    static public let kTinodePrefAppLaunchedBefore = "tinodePrefAppLaunchedBefore"

    static public let kTinodePrefTosUrl = "tinodePrefTosUrl"
    static public let kTinodePrefServiceName = "tinodePrefServiceName"
    static public let kTinodePrefPrivacyUrl = "tinodePrefPrivacyUrl"
    static public let kTinodePrefAppId = "tinodePrefAppId"
    static public let kTinodePrefSmallIcon = "tinodePrefSmallIcon"
    static public let kTinodePrefLargeIcon = "tinodePrefLargeIcon"

    // App Tinode api key.
    private static let kApiKey = "AQEAAAABAAD_rAp4DJh05a1HAwFT3A6K"

    static public let kAppDefaults = UserDefaults(suiteName: BaseDb.kAppGroupId)!
    static let kAppKeychain = KeychainWrapper(serviceName: "co.tinode.tinodios", accessGroup: BaseDb.kAppGroupId)

    // Keys we store in keychain.
    static let kTokenKey = "co.tinode.token"
    static let kTokenExpiryKey = "co.tinode.token_expiry"

    // Application metadata version.
    // Bump it up whenever you change the application metadata and
    // want to force the user to re-login when the user installs
    // this new application version.
    static let kAppMetaVersion = 1

    // Default connection params.
    #if DEBUG
        public static let kHostName = "127.0.0.1:6060" // localhost
        public static let kUseTLS = false
    #else
        public static let kHostName = "api.tinode.co" // production cluster
        public static let kUseTLS = true
    #endif

    // Returns true if the app is being launched for the first time.
    public static var isFirstLaunch: Bool {
        get {
            return !SharedUtils.kAppDefaults.bool(forKey: SharedUtils.kTinodePrefAppLaunchedBefore)
        }
        set {
            SharedUtils.kAppDefaults.set(!newValue, forKey: SharedUtils.kTinodePrefAppLaunchedBefore)
        }
    }

    // App TOS url string.
    public static var tosUrl: String? {
        get {
            return SharedUtils.kAppDefaults.string(forKey: SharedUtils.kTinodePrefTosUrl)
        }
        set {
            SharedUtils.kAppDefaults.set(newValue, forKey: SharedUtils.kTinodePrefTosUrl)
        }
    }

    // Application service name.
    public static var serviceName: String? {
        get {
            return SharedUtils.kAppDefaults.string(forKey: SharedUtils.kTinodePrefServiceName)
        }
        set {
            SharedUtils.kAppDefaults.set(newValue, forKey: SharedUtils.kTinodePrefServiceName)
        }
    }

    // Application privacy policy url.
    public static var privacyUrl: String? {
        get {
            return SharedUtils.kAppDefaults.string(forKey: SharedUtils.kTinodePrefPrivacyUrl)
        }
        set {
            SharedUtils.kAppDefaults.set(newValue, forKey: SharedUtils.kTinodePrefPrivacyUrl)
        }
    }

    // App's registration id in Tinode console.
    public static var appId: String? {
        get {
            return SharedUtils.kAppDefaults.string(forKey: SharedUtils.kTinodePrefAppId)
        }
        set {
            SharedUtils.kAppDefaults.set(newValue, forKey: SharedUtils.kTinodePrefAppId)
        }
    }

    // Apps' small icon.
    public static var smallIcon: UIImage? {
        get {
            if let data = SharedUtils.kAppDefaults.object(forKey: SharedUtils.kTinodePrefSmallIcon) as? Data {
                return UIImage(data: data)
            }
            return nil
        }
        set {
            SharedUtils.kAppDefaults.set(newValue?.pngData(), forKey: SharedUtils.kTinodePrefSmallIcon)
        }
    }

    // Apps' large icon.
    public static var largeIcon: UIImage? {
        get {
            if let data = SharedUtils.kAppDefaults.object(forKey: SharedUtils.kTinodePrefLargeIcon) as? Data {
                return UIImage(data: data)
            }
            return nil
        }
        set {
            SharedUtils.kAppDefaults.set(newValue?.pngData(), forKey: SharedUtils.kTinodePrefLargeIcon)
        }
    }

    public static func getSavedLoginUserName() -> String? {
        return SharedUtils.kAppDefaults.string(forKey: SharedUtils.kTinodePrefLastLogin)
    }
    private static func appMetaVersionUpToDate() -> Bool {
        let v = SharedUtils.kAppDefaults.integer(forKey: SharedUtils.kTinodeMetaVersion)
        guard v == SharedUtils.kAppMetaVersion else {
            BaseDb.log.error("App meta version does not match. Saved [%d] vs current [%d]", v, SharedUtils.kAppMetaVersion)
            // Clear the app keychain.
            SharedUtils.kAppKeychain.removeAllKeys()
            SharedUtils.kAppDefaults.set(SharedUtils.kAppMetaVersion, forKey: SharedUtils.kTinodeMetaVersion)
            return false
        }
        return true
    }

    public static func getAuthToken() -> String? {
        guard SharedUtils.appMetaVersionUpToDate() else { return nil }
        return SharedUtils.kAppKeychain.string(
            forKey: SharedUtils.kTokenKey, withAccessibility: .afterFirstUnlock)
    }

    public static func getAuthTokenExpiryDate() -> Date? {
         guard let expString = SharedUtils.kAppKeychain.string(
             forKey: SharedUtils.kTokenExpiryKey, withAccessibility: .afterFirstUnlock) else { return nil }
         return Formatter.rfc3339.date(from: expString)
    }

    public static func removeAuthToken() {
        SharedUtils.kAppDefaults.removeObject(forKey: SharedUtils.kTinodePrefLastLogin)
        SharedUtils.kAppKeychain.removeAllKeys()
    }

    public static func saveAuthToken(for userName: String, token: String?, expires expiryDate: Date?) {
        SharedUtils.kAppDefaults.set(userName, forKey: SharedUtils.kTinodePrefLastLogin)
        if let token = token, !token.isEmpty {
            if !SharedUtils.kAppKeychain.set(token, forKey: SharedUtils.kTokenKey, withAccessibility: .afterFirstUnlock) {
                BaseDb.log.error("Could not save auth token")
            }
            if let expiryDate = expiryDate {
                SharedUtils.kAppKeychain.set(
                    Formatter.rfc3339.string(from: expiryDate),
                    forKey: SharedUtils.kTokenExpiryKey,
                    withAccessibility: .afterFirstUnlock)
            } else {
                SharedUtils.kAppKeychain.removeObject(forKey: SharedUtils.kTokenExpiryKey)
            }
        }
    }

    /// Creates a Tinode instance backed by the local starage.
    public static func createTinode() -> Tinode {
        let appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        let appName = "Tinodios/" + appVersion
        let dbh = BaseDb.sharedInstance
        // FIXME: Get and use current UI language from Bundle.main.preferredLocalizations.first
        let tinode = Tinode(for: appName,
                            authenticateWith: SharedUtils.kApiKey,
                            persistDataIn: dbh.sqlStore)
        tinode.OsVersion = UIDevice.current.systemVersion
        return tinode
    }

    public static func registerUserDefaults() {
        /// Here you can give default values to your UserDefault keys
        SharedUtils.kAppDefaults.register(defaults: [
            SharedUtils.kTinodePrefReadReceipts: true,
            SharedUtils.kTinodePrefTypingNotifications: true
        ])

        let (hostName, _, _) = ConnectionSettingsHelper.getConnectionSettings()
        if hostName == nil {
            // If hostname is nil, sync values to defaults
            ConnectionSettingsHelper.setHostName(Bundle.main.object(forInfoDictionaryKey: "HOST_NAME") as? String)
            ConnectionSettingsHelper.setUseTLS(Bundle.main.object(forInfoDictionaryKey: "USE_TLS") as? String)
        }
        if !SharedUtils.appMetaVersionUpToDate() {
            BaseDb.log.info("App started for the first time.")
        }
    }

    public static func connectAndLoginSync(using tinode: Tinode, inBackground bkg: Bool) -> Bool {
        guard let userName = SharedUtils.getSavedLoginUserName(), !userName.isEmpty else {
            BaseDb.log.error("Connect&Login Sync - missing user name")
            return false
        }
        guard let token = SharedUtils.getAuthToken(), !token.isEmpty else {
            BaseDb.log.error("Connect&Login Sync - missing auth token")
            return false
        }
        if let tokenExpires = SharedUtils.getAuthTokenExpiryDate(), tokenExpires < Date() {
            // Token has expired.
            // TODO: treat tokenExpires == nil as a reason to reject.
            BaseDb.log.error("Connect&Login Sync - auth token expired")
            return false
        }
        BaseDb.log.info("Connect&Login Sync - will attempt to login (user name: %@)", userName)
        var success = false
        do {
            tinode.setAutoLoginWithToken(token: token)
            // Tinode.connect() will automatically log in.
            let msg = try tinode.connectDefault(inBackground: bkg)?.getResult()
            if let ctrl = msg?.ctrl {
                // Assuming success by default.
                success = true
                switch ctrl.code {
                case 0..<300:
                    let myUid = ctrl.getStringParam(for: "user")
                    BaseDb.log.info("Connect&Login Sync - login successful for: %@", myUid!)
                    if tinode.authToken != token {
                        SharedUtils.saveAuthToken(for: userName, token: tinode.authToken, expires: tinode.authTokenExpires)
                    }
                case 401:
                    BaseDb.log.info("Connect&Login Sync - attempt to subscribe to 'me' before login.")
                case 409:
                    BaseDb.log.info("Connect&Login Sync - already authenticated.")
                case 500..<600:
                    BaseDb.log.error("Connect&Login Sync - server error on login: %d", ctrl.code)
                default:
                    success = false
                }
            }
        } catch WebSocketError.network(let err) {
            // No network connection.
            BaseDb.log.debug("Connect&Login Sync [network] - could not connect to Tinode: %@", err)
            success = true
        } catch {
            let err = error as NSError
            if err.code == NSURLErrorCannotConnectToHost {
                BaseDb.log.debug("Connect&Login Sync [network] - could not connect to Tinode: %@", err)
                success = true
            } else {
                BaseDb.log.error("Connect&Login Sync - failed to automatically login to Tinode: %@", error.localizedDescription)
            }
        }
        return success
    }

    // Synchronously fetches description for topic |topicName|
    // (and saves the description locally).
    @discardableResult
    public static func fetchDesc(using tinode: Tinode, for topicName: String) -> UIBackgroundFetchResult {
        guard tinode.isConnectionAuthenticated || SharedUtils.connectAndLoginSync(using: tinode, inBackground: true) else {
            return .failed
        }
        // If we have topic data, we are done.
        guard !tinode.isTopicTracked(topicName: topicName) else {
            return .noData
        }
        do {
            if let msg = try tinode.getMeta(topic: topicName, query: MsgGetMeta.desc()).getResult(),
                (msg.ctrl?.code ?? 500) < 300 {
                return .newData
            }
        } catch {
            BaseDb.log.error("Failed to fetch topic description for [%@]: %@", topicName, error.localizedDescription)
        }
        return .failed
    }

    // Synchronously connects to topic |topicName| and fetches its messages
    // if the last received message was prior to |seq|.
    @discardableResult
    public static func fetchData(using tinode: Tinode, for topicName: String, seq: Int, keepConnection: Bool) -> UIBackgroundFetchResult {
        guard tinode.isConnectionAuthenticated || SharedUtils.connectAndLoginSync(using: tinode, inBackground: true) else {
            return .failed
        }
        var topic: DefaultComTopic
        var builder: DefaultComTopic.MetaGetBuilder
        if !tinode.isTopicTracked(topicName: topicName) {
            // New topic. Create it.
            guard let t = tinode.newTopic(for: topicName) as? DefaultComTopic else {
                return .failed
            }
            topic = t
            builder = topic.metaGetBuilder().withDesc().withSub()
        } else {
            // Existing topic.
            guard let t = tinode.getTopic(topicName: topicName) as? DefaultComTopic else { return .failed }
            topic = t
            builder = topic.metaGetBuilder()
        }

        guard !topic.attached else {
            // No need to fetch: topic is already subscribed and got data through normal channel.
            return .noData
        }
        if (topic.recv ?? 0) >= seq {
            return .noData
        }
        if let msg = try? topic.subscribe(set: nil, get: builder.withLaterData(limit: 10).withDel().build()).getResult(), (msg.ctrl?.code ?? 500) < 300 {
            if !keepConnection {
                // Data messages are sent asynchronously right after ctrl message.
                // Give them 1 second to arrive - so we reply back with {note recv}.
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                    if topic.attached {
                        topic.leave()
                    }
                }
            }
            return .newData
        }
        return .failed
    }


    // Update cached seq id of the last read message.
    public static func updateRead(using tinode: Tinode, for topicName: String, seq: Int) -> UIBackgroundFetchResult {
        // Don't need to handle 'read' notifications for an unknown topic.
        guard let topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic else { return .failed }

        if topic.read ?? -1 < seq {
            topic.read = seq
            if let store = BaseDb.sharedInstance.sqlStore {
                _ = store.setRead(topic: topic, read: seq)
            }
        }
        return .noData
    }

    // Downloads an image.
    private static func downloadIcon(fromPath path: String, relativeTo baseUrl: URL, completion: @escaping ((UIImage?) -> Void)) {
        print("Downloading icon: ", path, baseUrl)
        guard let url = URL(string: path, relativeTo: baseUrl) else {
            print("Invalid icon url: ", path, baseUrl.absoluteString)
            completion(nil)
            return
        }
        let task = URLSession.shared.dataTask(with: URLRequest(url: url)) { data, req, error in
            if let error = error {
                print(error.localizedDescription)
            }
            completion(data != nil ? UIImage(data: data!) : nil)
        }
        task.resume()
    }

    // Identifies device with Tinode server and fetches branding configuration code.
    public static func identifyAndConfigureBranding() {
        let device = UIDevice.current.userInterfaceIdiom == .phone ? "iphone" : UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : ""
        let version = UIDevice.current.systemVersion
        let url = URL(string: "https://hosts.tinode.co/whoami?os=ios-\(version)&dev=\(device)")!
        print("Self-identifying with the server. Endpoint: ", url.absoluteString)
        let task = URLSession.shared.dataTask(with: URLRequest(url: url)) { data, response, error in
            guard let data = data, error == nil else {
                print("Branding config response error: " + (error?.localizedDescription ?? "Failed to self-identify"))
                return
            }
            let responseJSON = try? JSONSerialization.jsonObject(with: data, options: [])
            if let responseJSON = responseJSON as? [String: Any] {
                print("Branding identity config: ", responseJSON)

                if let code = responseJSON["code"] as? String {
                    SharedUtils.setUpBranding(withConfigurationCode: code)
                } else {
                    print("Branding config error: Missing configuration code in the response. Quitting.")
                }
            }
        }
        task.resume()
    }

    // Configures application branding and connection settings.
    public static func setUpBranding(withConfigurationCode configCode: String) {
        guard !configCode.isEmpty else {
            print("Branding configuration code may not be empty. Skipping branding config.")
            return
        }
        print("Configuring branding with code '\(configCode)'")
        // Dummy url.
        // TODO: url should be based on the device fp (e.g. UIDevice.current.identifierForVendor).
        let url = URL(string: "https://hosts.tinode.co/id/\(configCode)")!

        print("Configuring branding and app settings. Request url: ", url.absoluteString)
        let task = URLSession.shared.dataTask(with: URLRequest(url: url)) { data, response, error in
            guard let data = data, error == nil else {
                print(error?.localizedDescription ?? "No data")
                return
            }
            let responseJSON = try? JSONSerialization.jsonObject(with: data, options: [])
            if let responseJSON = responseJSON as? [String: Any] {
                print("Branding configuration: ", responseJSON)

                if let tosUrl = URL(string: responseJSON["tos_url"] as? String ?? "") {
                    SharedUtils.tosUrl = tosUrl.absoluteString
                }
                if let serviceName = responseJSON["service_name"] as? String {
                    SharedUtils.serviceName = serviceName
                }
                if let privacyUrl  = URL(string: responseJSON["privacy_url"] as? String ?? "") {
                    SharedUtils.privacyUrl = privacyUrl.absoluteString
                }
                if let apiUrl = URL(string: responseJSON["api_url"] as? String ?? "") {
                    ConnectionSettingsHelper.setHostName(apiUrl.host!)
                    let useTls = ["https", "ws"].contains(apiUrl.scheme)
                    ConnectionSettingsHelper.setUseTLS(useTls ? "true" : "false")
                }
                if let id = responseJSON["id"] as? String {
                    SharedUtils.appId = id
                }

                // Send a notification so all interested parties may use branding config.
                NotificationCenter.default.post(name: Notification.Name(SharedUtils.kNotificationBrandingConfigAvailable), object: nil)
                // Icons.
                if let assetsBase = responseJSON["assets_base"] as? String, let base = URL(string: assetsBase) {
                    if let smallIcon = responseJSON["icon_small"] as? String {
                        downloadIcon(fromPath: smallIcon, relativeTo: base) { img in
                            guard let img = img else { return }
                            SharedUtils.smallIcon = img
                            // Send notifications so all interested parties may use the new icon.
                            NotificationCenter.default.post(name: Notification.Name(SharedUtils.kNotificationBrandingSmallIconAvailable), object: img)
                        }
                    }
                    if let largeIcon = responseJSON["icon_large"] as? String {
                        downloadIcon(fromPath: largeIcon, relativeTo: base) { img in
                            guard let img = img else { return }
                            SharedUtils.largeIcon = img
                        }
                    }
                }
            }
        }
        task.resume()
    }
}

extension Tinode {
    public static func getConnectionParams() -> (String, Bool) {
        let (hostName, useTLS, _) = ConnectionSettingsHelper.getConnectionSettings()
        return (hostName ?? SharedUtils.kHostName, useTLS ?? SharedUtils.kUseTLS)
    }

    @discardableResult
    public func connectDefault(inBackground bkg: Bool) throws -> PromisedReply<ServerMessage>? {
        let (hostName, useTLS) = Tinode.getConnectionParams()
        BaseDb.log.debug("Connecting to %@, secure %@", hostName, useTLS ? "YES" : "NO")
        return try connect(to: hostName, useTLS: useTLS, inBackground: bkg)
    }
}
