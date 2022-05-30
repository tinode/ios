//
//  CallManager.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK
import CallKit

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
    var callController: CXCallController!

    var callInProgress: Call?

    init() {
        callDelegate = CallProviderDelegate(callManager: self)
        callController = CXCallController()
    }

    // Report incoming call to the operating system (which displays incoming call UI).
    func displayIncomingCall(uuid: UUID, topic: String, from: String, seqId: Int, completion: ((Error?) -> Void)?) {
        guard self.callInProgress == nil else {
            let tinode = Cache.tinode
            tinode.videoCall(topic: topic, seq: seqId, event: "hang-up")
            completion?(CallError.busy("Busy. Another call in progress"))
            return
        }
        self.callInProgress = Call(uuid: uuid, topic: topic, from: from, seq: seqId)
        let tinode = Cache.tinode
        let user: DefaultUser? = tinode.getUser(with: from)
        let senderName = user?.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name")
        callDelegate.reportIncomingCall(uuid: uuid, handle: senderName, completion: completion)
    }
}

extension CallManager: CallManagerImpl {
    func acceptPendingCall() -> Bool {
        guard let call = self.callInProgress else { return false }
        UiUtils.routeToMessageVC(forTopic: call.topic) { messageVC in
            messageVC.performSegue(withIdentifier: "Messages2Call", sender: call)
        }
        return true
    }

    func completeCallInProgress(reportToSystem: Bool, reportToPeer: Bool) {
        guard let call = self.callInProgress else { return }
        self.callInProgress = nil

        if reportToPeer {
            // Tell the peer the call is over/declined.
            Cache.tinode.videoCall(topic: call.topic, seq: call.seq, event: "hang-up")
        }
        if reportToSystem {
            // Tell the OS that the call is over/declined.
            let endCallAction = CXEndCallAction(call: call.uuid)
            let transaction = CXTransaction(action: endCallAction)

            self.callController.request(transaction) { error in
                if let error = error {
                    print("EndCallAction transaction request failed: \(error.localizedDescription).")
                    return
                }

                print("EndCallAction transaction request successful")
            }
        }
    }
}
