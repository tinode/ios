//
//  UiUtils.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

class UiTinodeEventListener : TinodeEventListener {
    // TODO: implement online/offline indicator changes.
    private var connected: Bool = false

    init(connected: Bool) {
        self.connected = connected
    }
    func onConnect(code: Int, reason: String, params: [String : JSONValue]?) {
        connected = true
    }
    func onDisconnect(byServer: Bool, code: Int, reason: String) {
        connected = false
    }
    func onLogin(code: Int, text: String) {}
    func onMessage(msg: ServerMessage?) {}
    func onRawMessage(msg: String) {}
    func onCtrlMessage(ctrl: MsgServerCtrl?) {}
    func onDataMessage(data: MsgServerData?) {}
    func onInfoMessage(info: MsgServerInfo?) {}
    func onMetaMessage(meta: MsgServerMeta?) {}
    func onPresMessage(pres: MsgServerPres?) {}
}
