//
//  MessageInteractor.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

protocol MessageBusinessLogic: class {
    @discardableResult
    func setup(topicName: String?) -> Bool
    @discardableResult
    func attachToTopic() -> Bool
    func cleanup()

    func sendMessage(content: Drafty) -> Bool
    func sendReadNotification()
}

protocol MessageDataStore {
    var topicName: String? { get set }
    var topic: DefaultComTopic? { get set }
    func setup(topicName: String?) -> Bool
    func loadMessages()
    func loadNextPage()
} 

class MessageInteractor: DefaultComTopic.Listener, MessageBusinessLogic, MessageDataStore {
    class MessageEventListener: UiTinodeEventListener {
        private weak var interactor: MessageBusinessLogic?
        init(interactor: MessageBusinessLogic?, connected: Bool) {
            super.init(connected: connected)
            self.interactor = interactor
        }
        override func onLogin(code: Int, text: String) {
            super.onLogin(code: code, text: text)
            _ = UiUtils.attachToMeTopic(meListener: nil)
            _ = interactor?.attachToTopic()
        }
    }
    static let kMessagesPerPage = 20
    var pagesToLoad: Int = 0
    var topicId: Int64?
    var topicName: String?
    var topic: DefaultComTopic?
    var presenter: MessagePresentationLogic?
    var messages: [StoredMessage] = []
    private var messageSenderQueue = DispatchQueue(label: "co.tinode.messagesender")
    private var tinodeEventListener: MessageEventListener? = nil

    func setup(topicName: String?) -> Bool {
        guard let topicName = topicName else { return false }
        self.topicName = topicName
        self.topicId = BaseDb.getInstance().topicDb?.getId(topic: topicName)
        let tinode = Cache.getTinode()
        self.tinodeEventListener = MessageEventListener(
            interactor: self, connected: tinode.isConnected)
        tinode.listener = self.tinodeEventListener
        self.topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic
        self.pagesToLoad = 1

        if let pub = self.topic?.pub {
            DispatchQueue.main.async {
                self.presenter?.updateTitleBar(icon: pub.photo?.image(), title: pub.fn)
            }
        }
        self.topic?.listener = self
        return self.topic != nil
    }
    func cleanup() {
        // set listeners to nil
        print("cleaning up the topic \(String(describing: self.topicName))")
        self.topic?.listener = nil
        if self.topic?.attached ?? false {
            self.topic?.leave()
        }
        Cache.getTinode().listener = nil
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
                    .build())?.then(
                    onSuccess: { [weak self] msg in
                        print("subscribed to topic")
                        self?.messageSenderQueue.async {
                            _ = self?.topic?.syncAll()
                        }
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
        defer {
            loadMessages()
        }
        do {
            _ = try topic.publish(content: content)?.then(
                onSuccess: { [weak self] msg in
                    self?.loadMessages()
                    return nil
                }, onFailure: { err in
                    // todo: display a UI toast.
                    return nil
                })
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
    func sendReadNotification() {
        self.topic?.noteRecv()
    }
    func loadMessages() {
        DispatchQueue.global(qos: .userInteractive).async {
            if let messages = BaseDb.getInstance().messageDb?.query(
                topicId: self.topicId,
                pageCount: self.pagesToLoad,
                pageSize: MessageInteractor.kMessagesPerPage) {
                DispatchQueue.main.async {
                    self.messages = messages
                    self.presenter?.presentMessages(messages: messages)
                }
            }
        }
    }

    private func loadNextPageInternal() -> Bool {
        if self.pagesToLoad * MessageInteractor.kMessagesPerPage == self.messages.count {
            self.pagesToLoad += 1
            self.loadMessages()
            return true
        }
        return false
    }

    func loadNextPage() {
        guard let t = self.topic else {
            self.presenter?.endRefresh()
            return
        }
        if !loadNextPageInternal() && !StoredTopic.isAllDataLoaded(topic: t) {
            do {
                try t.getMeta(query:
                    t.getMetaGetBuilder()
                        .withGetEarlierData(
                            limit: MessageInteractor.kMessagesPerPage)
                        .build())?.then(
                            onSuccess: { [weak self] msg in
                                self?.presenter?.endRefresh()
                                return nil
                            },
                            onFailure: { [weak self] err in
                                self?.presenter?.endRefresh()
                                return nil
                            })
            } catch {
                self.presenter?.endRefresh()
            }
        } else {
            self.presenter?.endRefresh()
        }
    }

    override func onData(data: MsgServerData?) {
        self.loadMessages()
    }
}
