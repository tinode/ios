//
//  CallManager.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK

class CallManager {
    public struct Call {
        var uuid: UUID
        var topic: String
        var from: String
        var seq: Int
    }
    
    enum CallError: Error {
        case busy(String)
    }

    var callDelegate: CallProviderDelegate!

    var callInProgress: Call?

    init() {
        callDelegate = CallProviderDelegate(callManager: self)
    }

    func displayIncomingCall(uuid: UUID, topic: String, from: String, seqId: Int, completion: ((Error?) -> Void)?) {
        guard self.callInProgress == nil else {
            completion?(CallError.busy("Busy. Another call in progress"))
            return
        }
        self.callInProgress = Call(uuid: uuid, topic: topic, from: from, seq: seqId)
        let tinode = Cache.tinode
        let user: DefaultUser? = tinode.getUser(with: from) //store.userGet(uid: from) as? DefaultUser
        let senderName = user?.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name")
        callDelegate.reportIncomingCall(uuid: uuid, handle: senderName, completion: completion)
    }
}

extension CallManager: CallManagerImpl {
    func canAccept(callWith uuid: UUID) -> Bool {
        guard let call = self.callInProgress else {
            return false
        }
        return call.uuid == uuid
    }

    func accept() {
        guard let call = self.callInProgress else { return }
        UiUtils.routeToMessageVC(forTopic: call.topic) { messageVC in
            messageVC.performSegue(withIdentifier: "Messages2Call", sender: call)
        }
    }

    func end() {
        self.callInProgress = nil
    }
}
