//
//  MessageInteractor.swift
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK
import TinodiosDB

// Pending part of the message to be sent.
public enum PendingMessage {
    // The user is replying to a message.
    case replyTo(message: Drafty, seqId: Int)
    // The user is forwarding a messsage.
    case forwarded(message: Drafty, from: String, preview: Drafty)
    // The user is editing a message.
    case edit(message: Drafty, markdown: String, seqId: Int)
}

protocol MessageBusinessLogic: AnyObject {
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

    func uploadAudio(_ def: UploadDef)
    func uploadFile(_ def: UploadDef)
    func uploadImage(_ def: UploadDef)
    func uploadVideo(_ def: UploadDef)

    func prepareQuoted(to msg: Message?, isReply: Bool) -> PromisedReply<PendingMessage>?
    func dismissPendingMessage()

    func createForwardedMessage(from original: Message?) -> PendingMessage?
    func prepareToForward(message: Drafty, forwardedFrom: String, preview: Drafty)
    var pendingMessage: PendingMessage? { get }
}

protocol MessageDataStore {
    var topicName: String? { get set }
    var topic: DefaultComTopic? { get set }
    func loadMessagesFromCache(scrollToMostRecentMessage: Bool)
    func loadPreviousPage()
    func deleteMessage(_ message: Message)
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
    var duration: Int?
    var preview: Data?
    var previewMime: String?
    var previewOutOfBand: Bool = false
}

class MessageInteractor: DefaultComTopic.Listener, MessageBusinessLogic, MessageDataStore {
    private static let kMessagesPerPage = 24

    public enum AttachmentType: Int {
        case audio // Audio record
        case file // File attachment
        case image // Image attachment
        case video // Video attachment
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

    var topicName: String?
    var topic: DefaultComTopic?
    var presenter: MessagePresentationLogic?

    private var pagesToLoad: Int = 0
    private var topicId: Int64?
    // Sorted by seq in ascending order.
    private var messages: [StoredMessage] = []
    private var messageInteractorQueue = DispatchQueue(label: "co.tinode.messageinteractor")
    private var tinodeEventListener: MessageEventListener?
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
    private var maxReadNoteSeqIdInFlight = -1

    // User provided setting for sending read notifications.
    private var sendReadReceipts = false

    // Only for .grp topics:
    // Keeps track of the known subscriptions for the given topic.
    private var knownSubs: Set<String> = []
    // True when new subscriptions were added to the topic.
    private var newSubsAvailable = false

    // Only if the user is replying to a message or forwarding a message.
    public var pendingMessage: PendingMessage?

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

        self.presenter?.updateTitleBar(pub: self.topic?.pub, online: (topic?.isChannel ?? false) ? nil : self.topic?.online, deleted: topic?.deleted ?? true)

        if let (maxRecv, maxRead) = self.topic?.maxRecvReadValues {
            self.lastSeenRead = maxRead
            self.lastSeenRecv = maxRecv
        }
        self.topic?.listener = self
        self.sendReadReceipts = sendReadReceipts
        // Keep track of subscriptions for group/channel topics.
        if let t = topic, t.isGrpType, let topicSubs = t.getSubscriptions() {
            for s in topicSubs {
                if let user = s.user {
                    knownSubs.insert(user)
                }
            }
        }
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
                                self?.loadMessagesFromCache()
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
                    self?.loadMessagesFromCache()
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

    private func senderName(for message: Message) -> String {
        var senderName: String?
        if let sub = topic?.getSubscription(for: message.from), let pub = sub.pub {
            senderName = pub.fn
        }
        return senderName ?? String(format: NSLocalizedString("Unknown %@", comment: ""), message.from ?? "none")
    }

    // Convert message into a quote ready for sending as a reply.
    func prepareQuoted(to msg: Message?, isReply: Bool) -> PromisedReply<PendingMessage>? {
        guard let msg = msg, let content = msg.content else {
            self.dismissPendingMessage()
            return nil
        }
        let seqId = msg.seqId
        let sender = senderName(for: msg)
        // Strip unneeded content and shorten.
        var reply = content.replyContent(length: UiUtils.kQuotedReplyLength, maxAttachments: 1)
        let createThumbnails = ThumbnailTransformer()
        reply = reply.transform(createThumbnails)
        let whenDone = PromisedReply<PendingMessage>()
        createThumbnails.completionPromise.thenApply {_ in
            if isReply {
                let finalMsg = Drafty.quote(quoteHeader: sender, authorUid: msg.from ?? "", quoteContent: reply)
                self.pendingMessage = .replyTo(message: finalMsg, seqId: seqId)
            } else {
                let original = content.toMarkdown(withPlainLinks: true)
                self.pendingMessage = .edit(message: reply.wrapInto(style: "QQ"), markdown: original, seqId: seqId)
            }
            try? whenDone.resolve(result: self.pendingMessage!)
            return nil
        }
        return whenDone
    }

    func dismissPendingMessage() {
        if case .edit(_, _, _) = self.pendingMessage {
            self.presenter?.clearInputField()
        }
        self.pendingMessage = nil
    }

    func createForwardedMessage(from original: Message?) -> PendingMessage? {
        guard let original = original, let content = original.content, let topicName = self.topicName else {
            return nil
        }
        let sender = "➦ " + senderName(for: original)
        guard let from = original.from ?? self.topicName else {
            Cache.log.error("prepareForwardedMessage error: could not determine sender id for message %@", content.string)
            return nil
        }
        let transformed = content.forwardedContent()
        let forwardedContent = Drafty.mention(userWithName: sender, uid: from)
            .appendLineBreak()
            .append(transformed)
        let fwdHeader = "\(topicName):\(original.seqId)"

        // Preview of forwarded text.
        let preview = Drafty.quote(quoteHeader: sender, authorUid: from, quoteContent: transformed.preview(previewLen: UiUtils.kQuotedReplyLength))
        return .forwarded(message: forwardedContent, from: fwdHeader, preview: preview)
    }

    // Saves the pending forwarded message.
    func prepareToForward(message: Drafty, forwardedFrom: String, preview: Drafty) {
        self.pendingMessage = .forwarded(message: message, from: forwardedFrom, preview: preview)
    }

    func sendMessage(content: Drafty) {
        guard let topic = self.topic else { return }
        defer {
            loadMessagesFromCache()
        }
        var message = content
        var head: [String: JSONValue]? = nil
        if let pendingMsg = self.pendingMessage {
            // If we have a pending message, handle it.
            switch pendingMsg {
            case .replyTo(let replyTo, let replyToSeq):
                message = replyTo.append(message)
                head = ["reply": .string(String(replyToSeq))]
            case .forwarded(let forwardedMsg, let origin, _):
                message = forwardedMsg
                head = ["forwarded": .string(origin)]
            case .edit(_, _, let replaceSeq):
                head = ["replace": .string(":" + String(replaceSeq))]
            }
        }
        topic.publish(content: message, withExtraHeaders: head).then(
            onSuccess: { [weak self] _ in
                self?.loadMessagesFromCache()
                return nil
            },
            onFailure: { err in
                Cache.log.error("sendMessage error: %@", err.localizedDescription)
                if let e = err as? TinodeError {
                    if case .notConnected(_) = e {
                        DispatchQueue.main.async { UiUtils.showToast(message: NSLocalizedString("You are offline.", comment: "Toast notification")) }
                        Cache.tinode.reconnectNow(interactively: false, reset: false)
                        return nil
                    }
                }
                DispatchQueue.main.async { UiUtils.showToast(message: NSLocalizedString("Message not sent.", comment: "Toast notification")) }
                return nil
            }
        ).thenFinally {
            self.dismissPendingMessage()
            self.presenter?.dismissPendingMessagePreviewBar()
        }
    }

    func sendReadNotification(explicitSeq: Int? = nil, when deadline: DispatchTime) {
        guard self.sendReadReceipts else { return }
        // We don't send a notification if more notifications are pending.
        // This avoids the case of acking every {data} message in a large batch.
        // However, we send the max seq id in the batch.
        var doScheduleNotification = false
        messageInteractorQueue.sync {
            if self.maxReadNoteSeqIdInFlight < 0 {
                // Currently, no notifications are scheduled.
                doScheduleNotification = true
            }
            let es = explicitSeq ?? 0
            if es > self.maxReadNoteSeqIdInFlight {
                self.maxReadNoteSeqIdInFlight = es
            }
        }
        guard doScheduleNotification else { return }
        messageInteractorQueue.asyncAfter(deadline: deadline) { [weak self] in
            guard let explicitSeq = self?.maxReadNoteSeqIdInFlight else { return }
            self?.topic?.noteRead(explicitSeq: explicitSeq > 0 ? explicitSeq : nil)
            self?.maxReadNoteSeqIdInFlight = -1
        }
    }
    func sendTypingNotification() {
        topic?.noteKeyPress()
    }

    /// Load the most recent `kMessagesPerPage` messages from cache.
    func loadMessagesFromCache(scrollToMostRecentMessage: Bool = true) {
        guard let t = self.topic else { return }
        let numToLoad = self.pagesToLoad * MessageInteractor.kMessagesPerPage
        self.messageInteractorQueue.async {
            if let messagePage = BaseDb.sharedInstance.sqlStore?.getMessagePage(topic: t, from: Int.max, limit: numToLoad, forward: false) {
                // Replace messages with the new page.
                self.messages = messagePage.map { $0 as! StoredMessage }.reversed()
                self.presenter?.presentMessages(messages: self.messages, scrollToMostRecentMessage)
            }
        }
    }

    // Browsing backwards: load page from cache amd maybe from server.
    func loadPreviousPage() {
        guard let t = self.topic else {
            self.presenter?.endRefresh()
            return
        }

        let firstSeqId = self.messages.first?.seqId ?? Int.max
        if firstSeqId <= 1 {
            self.presenter?.endRefresh()
            return
        }

        if self.messages.count <= self.pagesToLoad * MessageInteractor.kMessagesPerPage {
            self.pagesToLoad += 1
        }

        self.messageInteractorQueue.async {
            t.loadMessagePage(startWithSeq: firstSeqId, pageSize: MessageInteractor.kMessagesPerPage, forward: false, onLoaded: { [weak self] (messagePage, error) in
                self?.presenter?.endRefresh()
                if let err = error {
                    Cache.log.error("Failed to load message page: %@", err.localizedDescription)
                } else if let messagePage = messagePage, !messagePage.isEmpty {
                    var page = messagePage.map { $0 as! StoredMessage }
                    // Page is returned in descending order, reverse.
                    page.reverse()
                    // Append older messages to the end of the fetched page.
                    page.append(contentsOf: self?.messages ?? [])
                    self?.messages = page
                    if self != nil {
                        self!.presenter?.presentMessages(messages: self!.messages, false)
                    }
                }
            })
        }
    }

    func deleteMessage(_ message: Message) {
        guard let topic = topic, let store = topic.store else {
            return
        }
        var seqIds: [Int] = []
        if let replSeq = message.replacesSeq, let versionSeqIds = topic.store?.getAllMsgVersions(fromTopic: topic, forSeq: replSeq, limit: nil) {
            for seq in versionSeqIds {
                if TopicDb.isUnsentSeq(seq: seq) {
                    store.msgDiscard(topic: topic, seqId: seq)
                } else {
                    seqIds.append(seq)
                }
            }
        }
        if message.isSynced {
            seqIds.append(message.seqId)
        } else {
            store.msgDiscard(topic: topic, dbMessageId: message.msgId)
        }
        topic.delMessages(ids: seqIds, hard: false).then(
            onSuccess: { [weak self] _ in
                self?.loadMessagesFromCache()
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler)
        self.loadMessagesFromCache()
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
                onSuccess: { _ in
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
        response.thenApply({ _ in
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
        var result: MessageInteractor?
        DispatchQueue.main.sync {
            guard let window = (UIApplication.shared.delegate as! AppDelegate).window, let navVC = window.rootViewController as? UINavigationController else {
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
        uploadMessageAttachment(type: .image, def)
    }

    func uploadFile(_ def: UploadDef) {
        uploadMessageAttachment(type: .file, def)
    }

    func uploadAudio(_ def: UploadDef) {
        uploadMessageAttachment(type: .audio, def)
    }

    func uploadVideo(_ def: UploadDef) {
        uploadMessageAttachment(type: .video, def)
    }

    private func uploadMessageAttachment(type: AttachmentType, _ def: UploadDef) {
        guard let mimeType = def.mimeType, let topic = topic else { return }

        let filename = def.filename ?? ""

        // Check if the attachment is too big even for out-of-band uploads.
        if def.data.count > Cache.tinode.getServerLimit(for: Tinode.kMaxFileUploadSize, withDefault: MessageViewController.kMaxAttachmentSize) {
            DispatchQueue.main.async {
                UiUtils.showToast(message: NSLocalizedString("Attachment exceeds maximum size", comment: "Error message: attachment too large"))
            }
            return
        }

        var replyToCopy: Drafty?
        if case let .replyTo(replyTo, _) = self.pendingMessage {
            replyToCopy = replyTo.copy()
        }

        // Giving fake URL to Drafty instead of Data which is not needed in DB anyway.
        guard let urlStr = "mid:uploading/\(filename)".addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else {
            DispatchQueue.main.async {
                UiUtils.showToast(message: String(format: NSLocalizedString("Failed to create URL string for file: %@", comment: "Error message: malformed URL string"), filename))
            }
            return
        }
        let ref = URL(string: urlStr)!
        var draft: Drafty?
        var previewData: Data?
        var head: [String: JSONValue]?
        switch type {
        case .audio:
            draft = MessageInteractor.draftyAudio(refurl: ref, mimeType: mimeType, data: nil, duration: def.duration!, preview: def.preview!, size: def.data.count)
            previewData = nil
        case .file:
            draft = MessageInteractor.draftyFile(filename: filename, refurl: ref, mimeType: mimeType, data: nil, size: def.data.count)
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
        case .video:
            draft = MessageInteractor.draftyVideo(caption: def.caption, mime: mimeType, refurl: ref, duration: def.duration!, width: Int(def.width!), height: Int(def.height!), fname: filename, size: def.data.count, preMime: def.previewMime, preview: def.preview, previewUrl: nil)
            previewData = def.preview
        }

        if let d = draft, case let .replyTo(replyTo, replyToSeq) = self.pendingMessage {
            draft = replyTo.append(d)
            head = ["reply": .string(String(replyToSeq))]
        }

        guard let content = draft else { return }
        // Dismiss reply.
        self.dismissPendingMessage()
        self.presenter?.dismissPendingMessagePreviewBar()

        if !content.isPlain {
            if head == nil {
                head = [:]
            }
            head!["mime"] = JSONValue.string(Drafty.kMimeType)
        }
        if let msg = topic.store?.msgDraft(topic: topic, data: content, head: head) {
            let helper = Cache.getLargeFileHelper()
            struct UploadResult {
                var result: ServerMessage?
                var error: Error?
            }
            let dg = DispatchGroup()

            var previewResult = UploadResult()
            if def.previewOutOfBand, let pdata = previewData {
                dg.enter()
                helper.startMsgAttachmentUpload(
                    filename: "preview:" + filename, mimetype: def.previewMime!, data: pdata,
                    topicId: self.topicName!, msgId: msg.msgId, progressCallback: nil,
                    completionCallback: { (srvMsg, err) in
                        previewResult.result = srvMsg
                        previewResult.error = err
                        dg.leave()
                    })
                previewData = nil
            }
            dg.enter()
            var attachmentResult = UploadResult()
            helper.startMsgAttachmentUpload(filename: filename, mimetype: mimeType, data: def.data, topicId: self.topicName!, msgId: msg.msgId, progressCallback: { [weak self] progress in
                    let interactor = self ?? MessageInteractor.existingInteractor(for: topic.name)
                    interactor?.presenter?.updateProgress(forMsgId: msg.msgId, progress: progress)
                },
                completionCallback: { (srvMsg, err) in
                    attachmentResult.result = srvMsg
                    attachmentResult.error = err
                    dg.leave()
                })

            dg.notify(queue: DispatchQueue.global(qos: .userInteractive)) { [weak self] in
                let serverMessage = attachmentResult.result
                let error = attachmentResult.error
                let interactor = self ?? MessageInteractor.existingInteractor(for: topic.name)
                var success = false
                defer {
                    if !success {
                        _ = topic.store?.msgDiscard(topic: topic, dbMessageId: msg.msgId)
                    }
                    interactor?.loadMessagesFromCache()
                }
                guard error == nil else {
                    switch error! {
                    case Upload.UploadError.cancelledByUser:
                        // Upload was cancelled by user. Do nothing.
                        Cache.log.info("Upload cancelled by user: file '%@'", filename)
                    default:
                        DispatchQueue.main.async {
                            UiUtils.showToast(message: error!.localizedDescription)
                        }
                    }
                    return
                }
                guard let ctrl = serverMessage?.ctrl, ctrl.code == 200, let srvUrl = URL(string: ctrl.getStringParam(for: "url") ?? "") else {
                    return
                }

                var draft: Drafty?
                switch type {
                case .audio:
                    draft = MessageInteractor.draftyAudio(refurl: ref, mimeType: mimeType, data: nil, duration: def.duration!, preview: def.preview!, size: def.data.count)
                case .file:
                    draft = try? Drafty().attachFile(mime: mimeType, fname: filename, refurl: srvUrl, size: def.data.count)
                case .image:
                    draft = MessageInteractor.draftyImage(caption: def.caption, filename: filename, refurl: srvUrl, mimeType: mimeType, data: previewData!, width: Int(def.width!), height: Int(def.height!), size: def.data.count)
                case .video:
                    var previewUrl: URL?
                    if let ctrl = previewResult.result?.ctrl, ctrl.code == 200 {
                        previewUrl = URL(string: ctrl.getStringParam(for: "url") ?? "")
                    }
                    draft = MessageInteractor.draftyVideo(caption: def.caption, mime: mimeType, refurl: srvUrl, duration: def.duration!, width: Int(def.width!), height: Int(def.height!), fname: filename, size: def.data.count, preMime: def.previewMime, preview: previewData, previewUrl: previewUrl)
                }
                if let r = replyToCopy, let d = draft {
                    draft = r.append(d)
                }

                if let content = draft {
                    _ = topic.store?.msgReady(topic: topic, dbMessageId: msg.msgId, data: content)
                    topic.syncOne(msgId: msg.msgId)
                        .thenFinally({
                            interactor?.loadMessagesFromCache()
                        })
                    success = true
                }
            }
            self.loadMessagesFromCache()
        }
    }

    private static func draftyFile(filename: String?, refurl: URL, mimeType: String?, data: Data?, size: Int) -> Drafty? {
        return try? Drafty().attachFile(mime: mimeType, bits: data, fname: filename, refurl: refurl, size: size)
    }

    private static func draftyImage(caption: String?, filename: String?, refurl: URL?, mimeType: String?, data: Data, width: Int, height: Int, size: Int) -> Drafty? {

        let content = Drafty(plainText: " ")
        let ref: URL?
        if let refurl = refurl, let base = Cache.tinode.baseURL(useWebsocketProtocol: false) {
            ref = URL(string: refurl.relativize(from: base))
        } else {
            ref = nil
        }

        try? _ = content.insertImage(at: 0, mime: mimeType, bits: data, width: width, height: height, fname: filename, refurl: ref, size: size)

        if let caption = caption, !caption.isEmpty {
            _ = content.appendLineBreak().append(Drafty(plainText: caption))
        }

        return content
    }

    private static func draftyAudio(refurl: URL?, mimeType: String?, data: Data?, duration: Int, preview: Data, size: Int) -> Drafty? {
        let ref: URL?
        if let refurl = refurl, let base = Cache.tinode.baseURL(useWebsocketProtocol: false) {
            ref = URL(string: refurl.relativize(from: base))
        } else {
            ref = nil
        }
        return try? Drafty(plainText: " ").insertAudio(at: 0, mime: mimeType, bits: data, preview: preview, duration: duration, fname: nil, refurl: ref, size: size)
    }

    private static func draftyVideo(caption: String?, mime: String, refurl: URL?,
                                    duration: Int, width: Int, height: Int, fname: String?, size: Int,
                                    preMime: String?, preview: Data?, previewUrl: URL?) -> Drafty? {
        let ref: URL?
        if let refurl = refurl, let base = Cache.tinode.baseURL(useWebsocketProtocol: false) {
            ref = URL(string: refurl.relativize(from: base))
        } else {
            ref = nil
        }
        let content = try? Drafty(plainText: " ").insertVideo(at: 0, mime: mime, bits: nil, refurl: ref, duration: duration, width: width, height: height, fname: fname, size: size, preMime: "image/png", preview: preview, previewRef: previewUrl)
        if let caption = caption, !caption.isEmpty {
            _ = content?.appendLineBreak().append(Drafty(plainText: caption))
        }
        return content
    }

    override func onData(data: MsgServerData?) {
        guard let data = data, let topic = topic else {
            self.loadMessagesFromCache()
            return
        }
        let newData = data.getSeq >= (topic.seq ?? 0)
        self.loadMessagesFromCache(scrollToMostRecentMessage: newData)
        if let from = data.from, let seq = data.seq, !Cache.tinode.isMe(uid: from) {
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
        if self.newSubsAvailable {
            self.newSubsAvailable = false
            // Reload messages so we can correctly display messages from
            // new users (subscriptions).
            self.presenter?.reloadAllMessages()
        }
    }
    override func onMetaDesc(desc: Description<TheCard, PrivateType>) {
        self.presenter?.applyTopicPermissions(withError: nil)
        if let pub = topic?.pub {
            let online = topic!.isChannel ? nil : topic!.online
            self.presenter?.updateTitleBar(pub: pub, online: online, deleted: topic!.deleted)
        }
    }
    override func onMetaSub(sub: Subscription<TheCard, PrivateType>) {
        guard let topic = topic else { return }
        if topic.isGrpType, let user = sub.user, !self.knownSubs.contains(user) {
            // New subscription.
            self.knownSubs.insert(user)
            self.newSubsAvailable = true
        }
    }
}
