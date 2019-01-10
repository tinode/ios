//
//  MessageInteractor.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

protocol MessageBusinessLogic {
    /*
    var currentUser: PCCurrentUser? { get set }
    
    func subscribeToRoom(room: PCRoom)
    func addChatMessage(request: Chatroom.Messages.Create.Request, completionHandler: @escaping (Int?, Error?) -> Void)
    func startedTyping(inRoom room: PCRoom)
    */
    @discardableResult
    func setup(topicName: String?) -> Bool
    @discardableResult
    func attachToTopic() -> Bool
    func cleanup()
}

protocol MessageDataStore {
    /*
    var contact: Contact? { get set }
    var currentUser: PCCurrentUser? { get set }
    */
    var topicName: String? { get set }
    var topic: DefaultComTopic? { get set }
    func setup(topicName: String?) -> Bool
}

class MessageInteractor: MessageBusinessLogic, MessageDataStore {
    /*
    
    var contact: Contact?
    var messages: [PCMessage] = []
    var currentUser: PCCurrentUser?
    var presenter: ChatroomPresentationLogic?
    */
    var topicName: String?
    var topic: DefaultComTopic?
    var presenter: MessagePresentationLogic?
    
    func setup(topicName: String?) -> Bool {
        guard let topicName = topicName else { return false }
        self.topicName = topicName
        let tinode = Cache.getTinode()
        self.topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic
        return self.topic != nil
    }
    func attachToTopic() -> Bool {
        do {
            try self.topic?.subscribe(
                set: nil,
                get: self.topic?.getMetaGetBuilder()
                    .withGetDesc()
                    .withGetSub()
                    .withGetData()
                    .withGetDel()
                    .build()).then(
                    onSuccess: { msg in
                        print("subscribed to topic")
                        //topic.syncAll()
                        return nil
                },
                    onFailure: { err in
                        // failed
                        print("failed \(err)")
                        return nil
                })
        } catch TinodeError.notConnected(let errorMsg) {
            // presenter --> show error message
            print("Tinode is not connected \(errorMsg)")
        } catch {
            print("Error subscribing to topic \(error)")
        }
        return false
    }
    func cleanup() {
        // set listeners to nil
        print("cleaning up the topic \(String(describing: self.topicName))")
        self.topic?.listener = nil
        if self.topic?.attached ?? false {
            do {
                try self.topic?.leave()
            } catch {
                print("Error leaving topic \(error)")
            }
        }
    }
}
