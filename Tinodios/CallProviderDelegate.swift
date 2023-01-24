//
//  CallProviderDelegate.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import CallKit

protocol CallManagerImpl: AnyObject {
    func acceptPendingCall() -> Bool
    func completeCallInProgress(reportToSystem: Bool, reportToPeer: Bool)
}

class CallProviderDelegate: NSObject, CXProviderDelegate {
    static let kProviderConfiguration: CXProviderConfiguration = {
        let providerConfiguration = CXProviderConfiguration(localizedName: "Tinode")  // TODO: change

        providerConfiguration.supportsVideo = true
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes = [.generic]
        providerConfiguration.includesCallsInRecents = false

        return providerConfiguration
    }()

    private weak var callManager: CallManagerImpl?
    private let provider: CXProvider

    init(callManager: CallManagerImpl?) {
        self.callManager = callManager
        self.provider = CXProvider(configuration: CallProviderDelegate.kProviderConfiguration)

        super.init()
        self.provider.setDelegate(self, queue: nil)
    }

    func reportIncomingCall(uuid: UUID, handle: String, audioOnly: Bool, completion: ((Error?) -> Void)?) {
      	let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        update.hasVideo = !audioOnly

        self.provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error = error {
                Cache.log.error("Report incoming call error: %@", error.localizedDescription)
            }
            completion?(error)
        }
    }

    func providerDidReset(_ provider: CXProvider) {
        callManager?.completeCallInProgress(reportToSystem: true, reportToPeer: true)
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // User tapped "Accept".
        if let cm = callManager, cm.acceptPendingCall() {
            action.fulfill()
        } else {
            action.fail()
        }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        // User tapped "Decline/End call" in the incoming call view,
        // or end call action was requested programmatically.
        callManager?.completeCallInProgress(reportToSystem: false, reportToPeer: true)
        action.fulfill()
    }
}
