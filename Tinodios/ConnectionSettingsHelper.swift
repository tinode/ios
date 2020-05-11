//
//  SettingsHelper.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

class ConnectionSettingsHelper {

    struct SettingsBundleKeys {
        static let hostName = "host_name_preference"
        static let useTLS = "use_tls_preference"
        static let wireTransport = "wire_transport_preference"
    }

    class func getConnectionSettings() -> (hostName: String?, useTLS: Bool?, wireTransport: String?) {
        return (hostName: UserDefaults.standard.string(forKey: SettingsBundleKeys.hostName), useTLS: UserDefaults.standard.bool(forKey: SettingsBundleKeys.useTLS), wireTransport: UserDefaults.standard.string(forKey: SettingsBundleKeys.wireTransport))
    }

    class func setHostName(_ hostName: String?) {
        guard hostName != nil else { return }
        UserDefaults.standard.set(hostName, forKey: SettingsBundleKeys.hostName)
    }

    class func setUseTLS(_ useTLS: String?) {
        guard let useTLS = useTLS else { return }
        UserDefaults.standard.set(NSString(string: useTLS).boolValue, forKey: SettingsBundleKeys.useTLS)
    }
}

