//
//  CallManager.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK
import CallKit
import WebRTC

class CallManager {
    private static let kCallTimeout = 30

    public struct Call {
        var uuid: UUID
        var topic: String
        var from: String
        var seq: Int
        var audioOnly: Bool
    }

    enum CallError: Error {
        case busy(String)
    }

    var callDelegate: CallProviderDelegate!
    var callController: CXCallController!
    var callInProgress: Call?
    // Dismisses call UI after timeout.
    var timer: Timer?

    // Returns true if the user originated the call.
    var currentCallIsOutgoing: Bool {
        guard let call = self.callInProgress else { return false }
        let tinode = Cache.tinode
        return tinode.isMe(uid: call.from)
    }

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

    // Utility function to configure RTCAudioSession.
    public static func audioSessionChange(action: ((RTCAudioSession) throws -> Void)) {
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.lockForConfiguration()
        do {
            try action(audioSession)
        } catch {
            Cache.log.error("WebRTCClient: error changing AVAudioSession: %@", error.localizedDescription)
        }
        audioSession.unlockForConfiguration()
    }

    public static func activateAudioSession(withSpeaker speaker: Bool) {
        self.audioSessionChange { audioSession in
            try audioSession.setCategory(AVAudioSession.Category.playAndRecord.rawValue)
            try audioSession.setMode(AVAudioSession.Mode.voiceChat.rawValue)
            try audioSession.overrideOutputAudioPort(speaker ? .speaker : .none)
            try audioSession.setActive(true)
        }
    }

    public static func deactivateAudioSession() {
        // Clean up audio.
        self.audioSessionChange { audioSession in
            try audioSession.setActive(false)
        }
    }

    // Registers an outgoing call that's just been started.
    func registerOutgoingCall(onTopic topicName: String, isAudioOnly: Bool) -> Bool {
        guard self.callInProgress == nil else {
            // Another call is in progress. Quit.
            return false
        }
        let tinode = Cache.tinode
        self.callInProgress = Call(uuid: UUID(), topic: topicName, from: tinode.myUid!, seq: -1, audioOnly: isAudioOnly)
        CallManager.activateAudioSession(withSpeaker: !isAudioOnly)
        Cache.log.info("Starting outgoing call (uuid: %@) on topic: %@", self.callInProgress!.uuid.uuidString, topicName)
        return true
    }

    // Sets seq id on the current call.
    func updateOutgoingCall(withNewSeqId seq: Int) {
        self.callInProgress?.seq = seq
    }

    // Report incoming call to the operating system (which displays incoming call UI).
    func displayIncomingCall(uuid: UUID, onTopic topicName: String, originatingFrom fromUid: String, withSeqId seq: Int, audioOnly: Bool, completion: ((Error?) -> Void)?) {
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

        self.callInProgress = Call(uuid: uuid, topic: topicName, from: fromUid, seq: seq, audioOnly: audioOnly)
        let tinode = Cache.tinode
        let user: DefaultUser? = tinode.getUser(with: fromUid)
        let senderName = user?.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name")
        callDelegate.reportIncomingCall(uuid: uuid, handle: senderName, audioOnly: audioOnly) { err in
            if err == nil {
                Cache.log.info("Reporting incoming call (uuid: %@) on topic: %@, seq: %d", self.callInProgress!.uuid.uuidString, topicName, seq)
                CallManager.activateAudioSession(withSpeaker: !audioOnly)
                tinode.videoCall(topic: topicName, seq: seq, event: "ringing")
                let timeout = (tinode.getServerParam(for: "callTimeout")?.asInt() ?? CallManager.kCallTimeout) + 5
                self.timer = self.makeCallTimeoutTimer(withDeadline: TimeInterval(timeout))
            } else {
                Cache.log.error("Incoming call (topic: %@, seq: %d) error: %@", topicName, seq, err!.localizedDescription)
                self.callInProgress = nil
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

        Cache.log.info("Accepting call: topic=%@, seq=%d", call.topic, call.seq)
        self.timer?.invalidate()
        self.timer = nil
        UiUtils.routeToMessageVC(forTopic: call.topic) { messageVC in
            guard let messageVC = messageVC else { return }
            Cache.log.info("Seguing from MessageVC to CallVC, topic=%@ -> %@", call.topic, messageVC)
            messageVC.performSegue(withIdentifier: "Messages2Call", sender: call)
        }
        return true
    }

    func completeCallInProgress(reportToSystem: Bool, reportToPeer: Bool) {
        guard let call = self.callInProgress else { return }
        Cache.log.info("Completing call: topic=%@, seq=%d", call.topic, call.seq)
        self.callInProgress = nil
        self.timer?.invalidate()
        self.timer = nil
        CallManager.deactivateAudioSession()

        if reportToPeer {
            // Tell the peer the call is over/declined.
            Cache.tinode.videoCall(topic: call.topic, seq: call.seq, event: "hang-up")
        }
        if reportToSystem {
            // Tell the OS that the call is over/declined.
            let endCallAction = CXEndCallAction(call: call.uuid)
            let transaction = CXTransaction(action: endCallAction)

            Cache.log.info("Ending call (uuid: %@) on topic: %@, seq: %d", call.uuid.uuidString, call.topic, call.seq)
            self.callController.request(transaction) { error in
                if let error = error {
                    Cache.log.error("CallManager - EndCallAction transaction request failed: %@", error.localizedDescription)
                    return
                }
            }
        }
    }
}
