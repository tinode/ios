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
    private static let kCallTimeout = 30

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
    // Dismisses call UI after timeout.
    var timer: Timer?

    init() {
        callDelegate = CallProviderDelegate(callManager: self)
        callController = CXCallController()
    }

    private func makeCallTimeoutTimer(withDeadline deadline: TimeInterval) -> Timer {
        return Timer.scheduledTimer(withTimeInterval: deadline, repeats: false) { timer in
            timer.invalidate()
            self.timer = nil
            if let call = self.callInProgress {
                self.dismissIncomingCall(onTopic: call.topic, withSeqId: call.seq)
            }
        }
    }

    // Registers an outgoing call that's just been started.
    func registerOutgoingCallStarted(onTopic topicName: String, withSeqId seq: Int) -> Bool {
        guard self.callInProgress == nil else {
            // Another call is in progress. Quit.
            return false
        }
        let tinode = Cache.tinode
        self.callInProgress = Call(uuid: UUID(), topic: topicName, from: tinode.myUid!, seq: seq)
        return true
    }

    // Report incoming call to the operating system (which displays incoming call UI).
    func displayIncomingCall(uuid: UUID, onTopic topicName: String, originatingFrom fromUid: String, withSeqId seq: Int, completion: ((Error?) -> Void)?) {
        guard self.callInProgress == nil else {
            if seq == self.callInProgress!.seq && self.callInProgress!.topic == topicName {
                // FIXME: this should not really happen. Find the source of duplicates and fix it.
                return
            }
            Cache.log.info("Hanging up: another call in progress")
            let tinode = Cache.tinode
            tinode.videoCall(topic: topicName, seq: seq, event: "hang-up")
            completion?(CallError.busy("Busy. Another call in progress"))
            return
        }

        self.callInProgress = Call(uuid: uuid, topic: topicName, from: fromUid, seq: seq)
        let tinode = Cache.tinode
        let user: DefaultUser? = tinode.getUser(with: fromUid)
        let senderName = user?.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name")
        callDelegate.reportIncomingCall(uuid: uuid, handle: senderName) { err in
            if err == nil {
                tinode.videoCall(topic: topicName, seq: seq, event: "ringing")
                let timeout = (tinode.getServerParam(for: "callTimeout")?.asInt() ?? CallManager.kCallTimeout) + 5
                self.timer = self.makeCallTimeoutTimer(withDeadline: TimeInterval(timeout))
            } else {
                Cache.log.error("Incoming call error: %@", err!.localizedDescription)
            }
            completion?(err)
        }
    }

    // Dismisses incoming call UI without displaying.
    func dismissIncomingCall(onTopic topic: String, withSeqId seq: Int) {
        guard let call = self.callInProgress, call.topic == topic, call.seq == seq else {
            return
        }
        self.completeCallInProgress(reportToSystem: true, reportToPeer: false)
    }
}

extension CallManager: CallManagerImpl {
    func acceptPendingCall() -> Bool {
        guard let call = self.callInProgress else { return false }
        self.timer?.invalidate()
        self.timer = nil
        UiUtils.routeToMessageVC(forTopic: call.topic) { messageVC in
            messageVC.performSegue(withIdentifier: "Messages2Call", sender: call)
        }
        return true
    }

    func completeCallInProgress(reportToSystem: Bool, reportToPeer: Bool) {
        guard let call = self.callInProgress else { return }
        self.callInProgress = nil
        self.timer?.invalidate()
        self.timer = nil

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
                    Cache.log.error("CallManager - EndCallAction transaction request failed: %@", error.localizedDescription)
                    return
                }
            }
        }
    }
}
