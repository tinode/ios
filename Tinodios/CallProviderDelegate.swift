//
//  CallProviderDelegate.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import CallKit

protocol CallManagerImpl: AnyObject {
    func canAccept(callWith uuid: UUID) -> Bool
    func accept()
    func end()
}

class CallProviderDelegate: NSObject, CXProviderDelegate {
    static let kProviderConfiguration: CXProviderConfiguration = {
        let providerConfiguration = CXProviderConfiguration(localizedName: "Tinode")  // TODO: change

        providerConfiguration.supportsVideo = true
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes = [.generic]

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

    func reportIncomingCall(uuid: UUID, handle: String, completion: ((Error?) -> Void)?) {
      	let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        update.hasVideo = true

        print("reporting new call with \(uuid) -> \(update)")
        self.provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if error != nil {
                print("got error: \(error)")
            }
            completion?(error)
        }
    }

    func providerDidReset(_ provider: CXProvider) {
        callManager?.end()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard callManager?.canAccept(callWith: action.callUUID) ?? false else {
            print("cannot accept... failing")
            action.fail()
            return
        }
        callManager?.accept()
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        callManager?.end()
        action.fulfill()
    }
}
