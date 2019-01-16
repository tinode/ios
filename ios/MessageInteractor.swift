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

    func sendMessage(content: Drafty) -> Bool
}

protocol MessageDataStore {
    /*
    var contact: Contact? { get set }
    var currentUser: PCCurrentUser? { get set }
    */
    var topicName: String? { get set }
    var topic: DefaultComTopic? { get set }
    func setup(topicName: String?) -> Bool
    func loadMessages()
}

class MessageInteractor: DefaultComTopic.Listener, MessageBusinessLogic, MessageDataStore {
    /*
    
    var contact: Contact?
    var messages: [PCMessage] = []
    var currentUser: PCCurrentUser?
    var presenter: ChatroomPresentationLogic?
    */
    static let kMessagesToLoad = 20
    var pagesToLoad: Int = 0
    var topicId: Int64?
    var topicName: String?
    var topic: DefaultComTopic?
    var presenter: MessagePresentationLogic?
    var messages: [StoredMessage] = []
    
    func setup(topicName: String?) -> Bool {
        guard let topicName = topicName else { return false }
        self.topicName = topicName
        self.topicId = BaseDb.getInstance().topicDb?.getId(topic: topicName)
        let tinode = Cache.getTinode()
        self.topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic
        self.pagesToLoad = 1
        return self.topic != nil
    }
    func attachToTopic() -> Bool {
        self.topic?.listener = self
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
    func sendMessage(content: Drafty) -> Bool {
        guard let topic = self.topic else { return false }
        do {
            _ = try topic.publish(content: content)?.then(
                onSuccess: { [weak self] msg in
                    self?.loadMessages()
                    return nil
                }, onFailure: { err in
                    // todo: display a UI toast.
                    return nil
                })
            loadMessages()
        } catch TinodeError.notConnected(let errMsg) {
            print("sendMessage -- not connected \(errMsg)")
            return false
        } catch {
            print("sendMessage failed \(error)")
            // todo: display a UI toast.
            return false
        }
        return true
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
    func loadMessages() {
        DispatchQueue.global(qos: .userInteractive).async {
            if let messages = BaseDb.getInstance().messageDb?.query(
                topicId: self.topicId,
                pageCount: self.pagesToLoad,
                pageSize: MessageInteractor.kMessagesToLoad) {
                DispatchQueue.main.async {
                    self.messages = messages
                    self.presenter?.presentMessages(messages: messages)
                }
            }
        }
    }
    override func onData(data: MsgServerData?) {
        self.loadMessages()
    }
}
