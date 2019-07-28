//
//  MessageInteractor.swift
//  Tinodios
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
    func leaveTopic()

    func sendMessage(content: Drafty) -> Bool
    func sendReadNotification()
    func sendTypingNotification()
    func enablePeersMessaging()
    func acceptInvitation()
    func ignoreInvitation()
    func blockTopic()
    func uploadFile(filename: String?, refurl: URL?, mimeType: String?, data: Data?)
}

protocol MessageDataStore {
    var topicName: String? { get set }
    var topic: DefaultComTopic? { get set }
    func setup(topicName: String?) -> Bool
    func loadMessages()
    func loadNextPage()
    func deleteMessage(seqId: Int)
} 

class MessageInteractor: DefaultComTopic.Listener, MessageBusinessLogic, MessageDataStore {
    class MessageEventListener: UiTinodeEventListener {
        private weak var interactor: MessageBusinessLogic?
        init(interactor: MessageBusinessLogic?, viewController: UIViewController?, connected: Bool) {
            super.init(viewController: viewController, connected: connected)
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

    @discardableResult
    func setup(topicName: String?) -> Bool {
        guard let topicName = topicName else { return false }
        self.topicName = topicName
        self.topicId = BaseDb.getInstance().topicDb?.getId(topic: topicName)
        let tinode = Cache.getTinode()
        if self.tinodeEventListener == nil {
            self.tinodeEventListener = MessageEventListener(
                interactor: self,
                viewController: self.presenter?.underlyingViewController,
                connected: tinode.isConnected)
        }
        tinode.listener = self.tinodeEventListener
        self.topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic
        self.pagesToLoad = 1

        if let pub = self.topic?.pub {
            DispatchQueue.main.async {
                self.presenter?.updateTitleBar(icon: pub.photo?.image(), title: pub.fn, online: self.topic?.online ?? false)
            }
        }
        self.topic?.listener = self
        return self.topic != nil
    }
    func cleanup() {
        // set listeners to nil
        print("cleaning up the topic \(String(describing: self.topicName))")
        if self.topic?.listener === self {
            self.topic?.listener = nil
        }
        let tinode = Cache.getTinode()
        if tinode.listener === self.tinodeEventListener {
            tinode.listener = nil
        }
    }
    func leaveTopic() {
        if self.topic?.attached ?? false {
            self.topic?.leave()
        }
    }
    func attachToTopic() -> Bool {
        guard !(self.topic?.attached ?? false) else {
            DispatchQueue.main.async { self.presenter?.applyTopicPermissions() }
            return true
        }
        do {
            try self.topic?.subscribe(
                set: nil,
                get: self.topic?.getMetaGetBuilder()
                    .withDesc()
                    .withSub()
                    .withData()
                    .withDel()
                    .build())?.then(
                    onSuccess: { [weak self] msg in
                        print("subscribed to topic")
                        self?.messageSenderQueue.async {
                            _ = self?.topic?.syncAll()
                        }
                        if self?.topicId == -1 {
                            self?.topicId = BaseDb.getInstance().topicDb?.getId(topic: self?.topicName)
                        }
                        self?.loadMessages()
                        DispatchQueue.main.async { self?.presenter?.applyTopicPermissions() }
                        return nil
                    },
                    onFailure: { err in
                        DispatchQueue.main.async {
                            UiUtils.showToast(
                                message: "Failed to subscribe to topic: \(err.localizedDescription)") }
                        if case TinodeError.notConnected(_) = err {
                            Cache.getTinode().reconnectNow()
                        }
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
                },
                onFailure: UiUtils.ToastFailureHandler)
        } catch TinodeError.notConnected(let errMsg) {
            print("sendMessage -- not connected \(errMsg)")
            DispatchQueue.main.async { UiUtils.showToast(message: "You are offline.") }
            Cache.getTinode().reconnectNow()
            return false
        } catch {
            print("sendMessage failed \(error)")
            DispatchQueue.main.async { UiUtils.showToast(message: "Message not sent.") }
            return false
        }
        return true
    }
    func sendReadNotification() {
        topic?.noteRecv()
        topic?.noteRead()
    }
    func sendTypingNotification() {
        topic?.noteKeyPress()
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
                        .withEarlierData(
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
    func deleteMessage(seqId: Int) {
        do {
            try topic?.delMessage(id: seqId, hard: false)?.then(
                onSuccess: { [weak self] msg in
                    self?.loadMessages()
                    return nil
                },
                onFailure: UiUtils.ToastFailureHandler)
            self.loadMessages()
        } catch TinodeError.notConnected(_) {
            UiUtils.showToast(message: "You are offline")
        } catch {
            UiUtils.showToast(message: "Action failed: \(error)")
        }
    }

    func enablePeersMessaging() {
        // Enable peer.
        guard let origAm = self.topic?.getSubscription(for: self.topic?.name)?.acs else { return }
        let am = Acs(from: origAm)
        guard am.given?.update(from: "+RW") ?? false else {
            return
        }
        do {
            try topic?.setMeta(meta: MsgSetMeta(
                desc: nil,
                sub: MetaSetSub(user: topic?.name, mode: am.givenString),
                tags: nil))?.thenCatch(onFailure: UiUtils.ToastFailureHandler)
        } catch TinodeError.notConnected(_) {
            UiUtils.showToast(message: "You are offline")
        } catch {
            UiUtils.showToast(message: "Action failed: \(error)")
        }
    }
    func acceptInvitation() {
        guard let topic = self.topic, let mode = self.topic?.accessMode?.givenString else { return }
        var response = topic.setMeta(meta: MsgSetMeta(desc: nil, sub: MetaSetSub(mode: mode), tags: nil))
        if topic.isP2PType {
            // For P2P topics change 'given' permission of the peer too.
            // In p2p topics the other user has the same name as the topic.
            do {
                response = try response?.thenApply(onSuccess: { msg in
                    _ = topic.setMeta(meta: MsgSetMeta(
                        desc: nil,
                        sub: MetaSetSub(user: topic.name, mode: mode),
                        tags: nil))
                    return nil
                })
            } catch TinodeError.notConnected(_) {
                UiUtils.showToast(message: "You are offline")
            } catch {
                UiUtils.showToast(message: "Operation failed \(error)")
            }
        }
        _ = try? response?.thenApply(onSuccess: { msg in
            self.presenter?.applyTopicPermissions()
            return nil
        })
    }
    func ignoreInvitation() {
        _ = try? self.topic?.delete()?.thenFinally(
            finally: {
                self.presenter?.dismiss()
                return nil
            })
    }
    func blockTopic() {
        guard let origAm = self.topic?.accessMode else { return }
        let am = Acs(from: origAm)
        guard am.want?.update(from: "-JP") ?? false else { return }
        do {
            try self.topic?.setMeta(meta: MsgSetMeta(desc: nil, sub: MetaSetSub(mode: am.wantString), tags: nil))?.thenFinally(
                finally: {
                    self.presenter?.dismiss()
                    return nil
                })
        } catch TinodeError.notConnected(_) {
            UiUtils.showToast(message: "You are offline")
        } catch {
            UiUtils.showToast(message: "Operation failed \(error)")
        }
    }
    static private func existingInteractor(for topicName: String?) -> MessageInteractor? {
        // Must be called on main thread.
        guard let topicName = topicName else { return nil }
        guard let window = UIApplication.shared.keyWindow, let navVC = window.rootViewController as? UINavigationController else {
            return nil
        }
        for controller in navVC.viewControllers {
            if let messageVC = controller as? MessageViewController, messageVC.topicName == topicName {
                return messageVC.interactor as? MessageInteractor
            }
        }
        return nil
    }
    func uploadFile(filename: String?, refurl: URL?, mimeType: String?, data: Data?) {
        guard let filename = filename, let mimeType = mimeType, let data = data, let topic = topic else { return }
        guard let content = try? Drafty().attachFile(mime: mimeType,
                                                bits: nil,
                                                fname: filename,
                                                refurl: refurl,
                                                size: data.count) else { return }
        if let msgId = topic.store?.msgDraft(topic: topic, data: content) {
            let helper = Cache.getLargeFileHelper()
            helper.startUpload(
                filename: filename, mimetype: mimeType, d: data,
                topicId: self.topicName!, msgId: msgId,
                progressCallback: { [weak self] progress in
                    DispatchQueue.main.async {
                        let interactor = self ?? MessageInteractor.existingInteractor(for: topic.name)
                        interactor?.presenter?.updateProgress(forMsgId: msgId, progress: progress)
                    }
                },
                completionCallback: { [weak self] (serverMessage, error) in
                    DispatchQueue.main.async {
                        let interactor = self ?? MessageInteractor.existingInteractor(for: topic.name)
                        var success = false
                        defer {
                            if !success {
                                _ = topic.store?.msgDiscard(topic: topic, dbMessageId: msgId)
                            }
                            interactor?.loadMessages()
                        }
                        guard error == nil else {
                            UiUtils.showToast(message: error!.localizedDescription)
                            return
                        }
                        guard let ctrl = serverMessage?.ctrl, ctrl.code == 200, let serverUrl = ctrl.getStringParam(for: "url") else {
                            return
                        }
                        if let srvUrl = URL(string: serverUrl), let content = try? Drafty().attachFile(
                            mime: mimeType, fname: filename,
                            refurl: srvUrl, size: data.count) {
                            _ = topic.store?.msgReady(topic: topic, dbMessageId: msgId, data: content)
                            _ = try? topic.syncOne(msgId: msgId)?.thenFinally(finally: {
                                interactor?.loadMessages()
                                return nil
                            })
                            success = true
                        }
                    }
                })
            self.loadMessages()
        }
    }
    override func onData(data: MsgServerData?) {
        self.loadMessages()
    }
    override func onPres(pres: MsgServerPres) {
        DispatchQueue.main.async { self.presenter?.applyTopicPermissions() }
    }
    override func onOnline(online: Bool) {
        DispatchQueue.main.async {
            self.presenter?.setOnline(online: online)
        }
    }
    override func onInfo(info: MsgServerInfo) {
        switch info.what {
        case "kp":
            DispatchQueue.main.async {
                self.presenter?.runTypingAnimation()
            }
        case "recv":
            fallthrough
        case "read":
            if let seqId = info.seq {
                DispatchQueue.main.async {
                    self.presenter?.reloadMessage(withSeqId: seqId)
                }
            }
        default:
            break
        }
    }
    override func onSubsUpdated() {
        DispatchQueue.main.async { self.presenter?.applyTopicPermissions() }
    }
    override func onMetaDesc(desc: Description<VCard, PrivateType>) {
        DispatchQueue.main.async { self.presenter?.applyTopicPermissions() }
    }
}
