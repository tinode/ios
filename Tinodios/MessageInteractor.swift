//
//  MessageInteractor.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK
import TinodiosDB

protocol MessageBusinessLogic: class {
    @discardableResult
    func setup(topicName: String?, sendReadReceipts: Bool) -> Bool
    @discardableResult
    func attachToTopic(interactively: Bool) -> Bool
    func cleanup()
    func leaveTopic()

    func sendMessage(content: Drafty)
    func sendReadNotification(explicitSeq: Int?, when deadline: DispatchTime)
    func sendTypingNotification()
    func enablePeersMessaging()
    func acceptInvitation()
    func ignoreInvitation()
    func blockTopic()
    func uploadFile(_ def: UploadDef)
    func uploadImage(_ def: UploadDef)
}

protocol MessageDataStore {
    var topicName: String? { get set }
    var topic: DefaultComTopic? { get set }
    func loadMessages()
    func loadNextPage()
    func deleteMessage(seqId: Int)
    func deleteFailedMessages()
} 

// Object to upload.
struct UploadDef {
    var caption: String?
    var filename: String?
    var mimeType: String?
    var image: UIImage?
    var data: Data
    var width: CGFloat?
    var height: CGFloat?
}

class MessageInteractor: DefaultComTopic.Listener, MessageBusinessLogic, MessageDataStore {
    public enum AttachmentType: Int {
        case file // File attachment
        case image // Image attachment
    }

    class MessageEventListener: UiTinodeEventListener {
        private weak var interactor: MessageBusinessLogic?
        init(interactor: MessageBusinessLogic?, connected: Bool) {
            super.init(connected: connected)
            self.interactor = interactor
        }
        override func onLogin(code: Int, text: String) {
            super.onLogin(code: code, text: text)
            _ = UiUtils.attachToMeTopic(meListener: nil)
            _ = interactor?.attachToTopic(interactively: false)
        }
    }
    static let kMessagesPerPage = 24
    var pagesToLoad: Int = 0
    var topicId: Int64?
    var topicName: String?
    var topic: DefaultComTopic?
    var presenter: MessagePresentationLogic?
    var messages: [StoredMessage] = []
    private var messageInteractorQueue = DispatchQueue(label: "co.tinode.messageinteractor")
    private var tinodeEventListener: MessageEventListener? = nil
    // Last reported recv and read seq ids by the onInfo handler.
    // Upon receipt of an info message, the handler will reload all messages with
    // seq ids between the last seen seq id (for recv and read messages respectively)
    // and the reported info.seq.
    // The new value for the variables below will be updated to info.seq.
    private var lastSeenRecv: Int?
    private var lastSeenRead: Int?

    // Maximum seq id of the currently scheduled read notifications.
    // -1 stands for no notifications in flight.
    //  0 means a notification without an explicit seq id has been requested.
    private var maxReadNoteSeqIdInFligth = -1

    // User provided setting for sending read notifications.
    private var sendReadReceipts = false

    @discardableResult
    func setup(topicName: String?, sendReadReceipts: Bool) -> Bool {
        guard let topicName = topicName else { return false }
        self.topicName = topicName
        self.topicId = BaseDb.sharedInstance.topicDb?.getId(topic: topicName)
        let tinode = Cache.tinode
        if self.tinodeEventListener == nil {
            self.tinodeEventListener = MessageEventListener(
                interactor: self,
                connected: tinode.isConnected)
        }
        tinode.addListener(self.tinodeEventListener!)
        self.topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic
        self.pagesToLoad = 1

        if let pub = self.topic?.pub {
            self.presenter?.updateTitleBar(icon: pub.photo?.image(), title: pub.fn, online: (topic?.isChannel ?? false) ? nil : self.topic?.online)
        }

        if let (maxRecv, maxRead) = self.topic?.maxRecvReadValues {
            self.lastSeenRead = maxRead
            self.lastSeenRecv = maxRecv
        }
        self.topic?.listener = self
        self.sendReadReceipts = sendReadReceipts
        return self.topic != nil
    }
    func cleanup() {
        // set listeners to nil
        if self.topic?.listener === self {
            self.topic?.listener = nil
        }

        if let listener = self.tinodeEventListener {
            Cache.tinode.removeListener(listener)
        }
    }
    func leaveTopic() {
        if self.topic?.attached ?? false {
            self.topic?.leave()
        }
    }
    func attachToTopic(interactively: Bool) -> Bool {
        guard let topic = self.topic, !topic.attached else {
            self.presenter?.applyTopicPermissions(withError: nil)
            return true
        }
        let tinode = Cache.tinode
        guard tinode.isConnectionAuthenticated else {
            // If connection is not ready, wait for completion.
            // MessageInteractor.attachToTopic() will be called again from the onLogin callback.
            tinode.reconnectNow(interactively: interactively, reset: false)
            return false
        }
        var builder = topic.metaGetBuilder()
            .withDesc()
            .withSub()
            .withLaterData(limit: MessageInteractor.kMessagesPerPage)
            .withDel()
        if topic.isOwner {
            builder = builder.withTags()
        }
        topic.subscribe(set: nil, get: builder.build()).then(
                onSuccess: { [weak self] msg in
                    // Check for topic redirects.
                    if let ctrl = msg?.ctrl, ctrl.code == ServerMessage.kStatusSeeOther {
                        if let redirectTo = ctrl.getStringParam(for: "topic") {
                            // Redirected to another topic
                            self?.presenter?.switchTopic(topic: redirectTo)
                            self?.setup(topicName: redirectTo, sendReadReceipts: interactively)
                            _ = self?.attachToTopic(interactively: interactively)
                        }
                        return nil
                    }
                    self?.messageInteractorQueue.async {
                        self?.topic?.syncAll().then(
                            onSuccess: { [weak self] _ in
                                self?.loadMessages()
                                return nil
                            },
                            onFailure: { err in
                                Cache.log.error("MessageInteractor - Failed to send pending messages: %@", err.localizedDescription)
                                return nil
                            }
                        )
                    }
                    if self?.topicId == -1 {
                        self?.topicId = BaseDb.sharedInstance.topicDb?.getId(topic: self?.topicName)
                    }
                    self?.loadMessages()
                    self?.presenter?.applyTopicPermissions(withError: nil)
                    return nil
                },
                onFailure: { [weak self] err in
                    let tinode = Cache.tinode
                    let errorMsg = String(format: NSLocalizedString("Failed to subscribe to topic: %@", comment: "Error message"), err.localizedDescription)
                    if tinode.isConnected {
                        DispatchQueue.main.async {
                            UiUtils.showToast(message: errorMsg)
                        }
                    } else {
                        Cache.log.error("MessageInteractor: %@", errorMsg)
                    }
                    switch err {
                    case TinodeError.notConnected(_):
                        tinode.reconnectNow(interactively: false, reset: false)
                    default:
                        self?.presenter?.applyTopicPermissions(withError: err)
                    }
                    return nil
                })

        return false
    }

    func sendMessage(content: Drafty) {
        guard let topic = self.topic else { return }
        defer {
            loadMessages()
        }
        topic.publish(content: content).then(
            onSuccess: { [weak self] msg in
                self?.loadMessages()
                return nil
            },
            onFailure: { err in
                Cache.log.error("sendMessage error: %@", err.localizedDescription)
                if let e = err as? TinodeError {
                    switch e {
                    case .notConnected(_):
                        DispatchQueue.main.async { UiUtils.showToast(message: NSLocalizedString("You are offline.", comment: "Toast notification")) }
                        Cache.tinode.reconnectNow(interactively: false, reset: false)
                    default:
                        DispatchQueue.main.async { UiUtils.showToast(message: NSLocalizedString("Message not sent.", comment: "Toast notification")) }
                    }
                }
                return nil
            }
        )
    }
    func sendReadNotification(explicitSeq: Int? = nil, when deadline: DispatchTime) {
        guard self.sendReadReceipts else { return }
        // We don't send a notification if more notifications are pending.
        // This avoids the case of acking every {data} message in a large batch.
        // However, we send the max seq id in the batch.
        var doScheduleNotification = false
        messageInteractorQueue.sync {
            if self.maxReadNoteSeqIdInFligth < 0 {
                // Currently, no notifications are scheduled.
                doScheduleNotification = true
            }
            let es = explicitSeq ?? 0
            if es > self.maxReadNoteSeqIdInFligth {
                self.maxReadNoteSeqIdInFligth = es
            }
        }
        guard doScheduleNotification else { return }
        messageInteractorQueue.asyncAfter(deadline: deadline) { [weak self] in
            guard let explicitSeq = self?.maxReadNoteSeqIdInFligth else { return }
            self?.topic?.noteRead(explicitSeq: explicitSeq > 0 ? explicitSeq : nil)
            self?.maxReadNoteSeqIdInFligth = -1
        }
    }
    func sendTypingNotification() {
        topic?.noteKeyPress()
    }

    func loadMessages() {
        self.messageInteractorQueue.async {
            if let messages = BaseDb.sharedInstance.messageDb?.query(
                    topicId: self.topicId,
                    pageCount: self.pagesToLoad,
                    pageSize: MessageInteractor.kMessagesPerPage,
                    descending: true) {
                self.messages = messages.reversed()
                self.presenter?.presentMessages(messages: self.messages)
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
            t.getMeta(query: t.metaGetBuilder()
                .withEarlierData(limit: MessageInteractor.kMessagesPerPage).build())
                .thenFinally({ [weak self] in
                    self?.presenter?.endRefresh()
                })
        } else {
            self.presenter?.endRefresh()
        }
    }

    func deleteMessage(seqId: Int) {
        topic?.delMessage(id: seqId, hard: false).then(
            onSuccess: { [weak self] msg in
                self?.loadMessages()
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler)
        self.loadMessages()
    }

    func deleteFailedMessages() {
        self.messageInteractorQueue.async {
            guard let t = self.topic else { return }
            _ = BaseDb.sharedInstance.sqlStore?.msgPruneFailed(topic: t)
        }
    }

    func enablePeersMessaging() {
        // Enable peer.
        guard let origAm = self.topic?.getSubscription(for: self.topic?.name)?.acs else { return }
        let am = Acs(from: origAm)
        guard am.given?.update(from: "+RW") ?? false else {
            return
        }
        topic?.setMeta(meta: MsgSetMeta(desc: nil, sub: MetaSetSub(user: topic?.name, mode: am.givenString), tags: nil, cred: nil)).thenCatch(UiUtils.ToastFailureHandler)
    }

    func acceptInvitation() {
        guard let topic = self.topic, let mode = self.topic?.accessMode?.givenString else { return }
        var response = topic.setMeta(meta: MsgSetMeta(desc: nil, sub: MetaSetSub(mode: mode), tags: nil, cred: nil))
        if topic.isP2PType {
            // For P2P topics change 'given' permission of the peer too.
            // In p2p topics the other user has the same name as the topic.
            response = response.then(
                onSuccess: { msg in
                    _ = topic.setMeta(meta: MsgSetMeta(
                        desc: nil,
                        sub: MetaSetSub(user: topic.name, mode: mode),
                        tags: nil,
                        cred: nil))
                    return nil
                },
                onFailure: UiUtils.ToastFailureHandler
            )
        }
        response.thenApply({ msg in
            self.presenter?.applyTopicPermissions(withError: nil)
            return nil
        })
    }
    func ignoreInvitation() {
        self.topic?.delete(hard: true)
            .thenFinally({
                self.presenter?.dismiss()
            })
    }

    func blockTopic() {
        guard let origAm = self.topic?.accessMode else { return }
        let am = Acs(from: origAm)
        guard am.want?.update(from: "-JP") ?? false else { return }
        self.topic?.setMeta(meta: MsgSetMeta(desc: nil, sub: MetaSetSub(mode: am.wantString), tags: nil, cred: nil))
            .thenCatch(UiUtils.ToastFailureHandler)
            .thenFinally({
                self.presenter?.dismiss()
            })
    }

    static private func existingInteractor(for topicName: String?) -> MessageInteractor? {
        // Must be called on main thread.
        guard let topicName = topicName else { return nil }
        var result: MessageInteractor? = nil
        DispatchQueue.main.sync {
            guard let window = UIApplication.shared.keyWindow, let navVC = window.rootViewController as? UINavigationController else {
                return
            }
            for controller in navVC.viewControllers {
                if let messageVC = controller as? MessageViewController, messageVC.topicName == topicName {
                    result = messageVC.interactor as? MessageInteractor
                    return
                }
            }
        }
        return result
    }

    func uploadImage(_ def: UploadDef) {
        uploadAttachment(type: .image, def)
    }

    func uploadFile(_ def: UploadDef) {
        uploadAttachment(type: .file, def)
    }

    private func uploadAttachment(type: AttachmentType, _ def: UploadDef) {
        guard let filename = def.filename, let mimeType = def.mimeType, let topic = topic else { return }

        // Check if the attachment is too big even for out-of-band uploads.
        if def.data.count > Cache.tinode.getServerLimit(for: Tinode.kMaxFileUploadSize, withDefault: MessageViewController.kMaxAttachmentSize) {
            DispatchQueue.main.async {
                UiUtils.showToast(message: NSLocalizedString("Attachment exceeds maximum size", comment: "Error message: attachment too large"))
            }
            return
        }

        // Giving fake URL to Drafty instead of Data which is not needed in DB anyway.
        let ref = URL(string: "mid:uploading/\(filename)")!
        let draft: Drafty?
        let previewData: Data?
        switch type {
        case .file:
            draft = MessageInteractor.draftyFile(filename: filename, refurl: ref, mimeType: mimeType, data: nil)
            previewData = nil
        case .image:
            let image = def.image!
            let data: Data
            if def.width! > UiUtils.kImagePreviewDimensions || def.height! > UiUtils.kImagePreviewDimensions {
                // Generate tiny image preview.
                let preview = image.resize(width: UiUtils.kImagePreviewDimensions, height: UiUtils.kImagePreviewDimensions, clip: false)
                previewData = preview?.pixelData(forMimeType: mimeType)
                data = previewData!
            } else {
                // The image is already tiny.
                data = def.data
                previewData = def.data
            }
            draft = MessageInteractor.draftyImage(caption: def.caption, filename: filename, refurl: ref, mimeType: mimeType, data: data, width: Int(def.width!), height: Int(def.height!), size: def.data.count)
        }

        guard let content = draft else { return }

        if let msgId = topic.store?.msgDraft(topic: topic, data: content, head: Tinode.draftyHeaders(for: content)) {
            let helper = Cache.getLargeFileHelper()
            helper.startUpload(
                filename: filename, mimetype: mimeType, d: def.data,
                topicId: self.topicName!, msgId: msgId,
                progressCallback: { [weak self] progress in
                    let interactor = self ?? MessageInteractor.existingInteractor(for: topic.name)
                    interactor?.presenter?.updateProgress(forMsgId: msgId, progress: progress)
                },
                completionCallback: { [weak self] (serverMessage, error) in
                    let interactor = self ?? MessageInteractor.existingInteractor(for: topic.name)
                    var success = false
                    defer {
                        if !success {
                            _ = topic.store?.msgDiscard(topic: topic, dbMessageId: msgId)
                        }
                        interactor?.loadMessages()
                    }
                    guard error == nil else {
                        DispatchQueue.main.async {
                            UiUtils.showToast(message: error!.localizedDescription)
                        }
                        return
                    }
                    guard let ctrl = serverMessage?.ctrl, ctrl.code == 200, let srvUrl = URL(string: ctrl.getStringParam(for: "url") ?? "") else {
                        return
                    }

                    let draft: Drafty?
                    switch type {
                    case .file:
                        draft = try? Drafty().attachFile(mime: mimeType, fname: filename, refurl: srvUrl, size: def.data.count)
                    case .image:
                        draft = MessageInteractor.draftyImage(caption: def.caption, filename: filename, refurl: srvUrl, mimeType: mimeType, data: previewData!, width: Int(def.width!), height: Int(def.height!), size: def.data.count)
                    }

                    if let content = draft {
                        _ = topic.store?.msgReady(topic: topic, dbMessageId: msgId, data: content)
                        topic.syncOne(msgId: msgId)
                            .thenFinally({
                                interactor?.loadMessages()
                            })
                        success = true
                    }
                })
            self.loadMessages()
        }
    }

    private static func draftyFile(filename: String?, refurl: URL, mimeType: String?, data: Data?) -> Drafty? {
        return try? Drafty().attachFile(mime: mimeType, bits: data, fname: filename, refurl: refurl, size: data?.count ?? 0)
    }

    private static func draftyImage(caption: String?, filename: String?, refurl: URL?, mimeType: String?, data: Data, width: Int, height: Int, size: Int) -> Drafty? {

        let content = Drafty(plainText: " ");
        let ref: URL?
        if let refurl = refurl, let base = Cache.tinode.baseURL(useWebsocketProtocol: false) {
            ref = URL(string: refurl.relativize(from: base))
        } else {
            ref = nil
        }

        try? _ = content.insertImage(at: 0, mime: mimeType, bits: data, width: width, height: height, fname: filename, refurl: ref, size: size);

        if let caption = caption, !caption.isEmpty {
            _ = content.appendLineBreak().append(Drafty(plainText: caption))
        }

        return content
    }

    override func onData(data: MsgServerData?) {
        self.loadMessages()
        if let from = data?.from, let seq = data?.seq, !Cache.tinode.isMe(uid: from) {
            sendReadNotification(explicitSeq: seq, when: .now() + .seconds(1))
        }
    }
    override func onPres(pres: MsgServerPres) {
        self.presenter?.applyTopicPermissions(withError: nil)
    }
    override func onOnline(online: Bool) {
        if !(self.topic?.isChannel ?? false) {
            self.presenter?.setOnline(online: online)
        }
    }
    override func onInfo(info: MsgServerInfo) {
        switch info.what {
        case "kp":
            self.presenter?.runTypingAnimation()
        case "recv":
            if let oldRecv = self.lastSeenRecv {
                if let newRecv = info.seq, oldRecv < newRecv {
                    self.presenter?.reloadMessages(fromSeqId: oldRecv + 1, toSeqId: newRecv)
                    self.lastSeenRecv = newRecv
                }
            } else {
                self.lastSeenRead = info.seq
                self.presenter?.reloadAllMessages()
            }
        case "read":
            if let oldRead = self.lastSeenRead {
                if let newRead = info.seq, oldRead < newRead {
                    self.presenter?.reloadMessages(fromSeqId: oldRead + 1, toSeqId: newRead)
                    self.lastSeenRead = newRead
                }
            } else {
                self.lastSeenRead = info.seq
                self.presenter?.reloadAllMessages()
            }
        default:
            break
        }
    }
    override func onSubsUpdated() {
        self.presenter?.applyTopicPermissions(withError: nil)
    }
    override func onMetaDesc(desc: Description<VCard, PrivateType>) {
        self.presenter?.applyTopicPermissions(withError: nil)
        if let pub = topic?.pub {
            let online = (self.topic?.isChannel ?? false) ? nil : self.topic?.online
            self.presenter?.updateTitleBar(icon: pub.photo?.image(), title: pub.fn, online: online)
        }
    }
}
