//
//  SettingsHelper.swift
//  TinodiosDB
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

public class ConnectionSettingsHelper {

    struct SettingsBundleKeys {
        static let hostName = "host_name_preference"
        static let useTLS = "use_tls_preference"
        static let wireTransport = "wire_transport_preference"
    }

    class func getConnectionSettings() -> (hostName: String?, useTLS: Bool?, wireTransport: String?) {
        return (hostName: SharedUtils.kAppDefaults.string(forKey: SettingsBundleKeys.hostName), useTLS: SharedUtils.kAppDefaults.bool(forKey: SettingsBundleKeys.useTLS), wireTransport: SharedUtils.kAppDefaults.string(forKey: SettingsBundleKeys.wireTransport))
    }

    class func setHostName(_ hostName: String?) {
        guard hostName != nil else { return }
        SharedUtils.kAppDefaults.set(hostName, forKey: SettingsBundleKeys.hostName)
    }

    class func setUseTLS(_ useTLS: String?) {
        guard let useTLS = useTLS else { return }
        SharedUtils.kAppDefaults.set(NSString(string: useTLS).boolValue, forKey: SettingsBundleKeys.useTLS)
    }
}
