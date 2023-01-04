//
//  MessageViewController+MessageCellDelegate.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import MobileVLCKit
import UIKit
import TinodeSDK

// Methods for handling taps in messages.

extension MessageViewController: MessageCellDelegate {
    func didLongTap(in cell: MessageCell) {
        createPopupMenu(in: cell)
    }

    func didTapContent(in cell: MessageCell, url: URL?) {
        guard let url = url else { return }

        if url.scheme == "tinode" {
            switch url.path {
            case "/post":
                handleButtonPost(in: cell, using: url)
            case "/attachment/small":
                handleSmallAttachment(in: cell, using: url)
            case "/attachment/large":
                handleLargeAttachment(in: cell, using: url)
            case "/image/preview":
                showImagePreview(in: cell, draftyEntityKey: Int(url.extractQueryParam(named: "key") ?? ""))
            case "/quote":
                handleQuoteClick(in: cell)
            case "/audio/seek":
                handleAudioSeek(in: cell, using: url)
                break
            case "/audio/toggle-play":
                handleToggleAudioPlay(in: cell, draftyEntityKey: Int(url.extractQueryParam(named: "key") ?? ""))
                break
            case "/video":
                showVideoPreview(in: cell, draftyEntityKey: Int(url.extractQueryParam(named: "key") ?? ""))
                break
            default:
                Cache.log.error("MessageVC - unknown tinode:// action: %@", url.description)
            }
            return
        }

        UIApplication.shared.open(url)
    }

    // TODO: remove as unused
    func didTapMessage(in cell: MessageCell) {}

    // TODO: remove as unused or go to user's profile (p2p topic?)
    func didTapAvatar(in cell: MessageCell) {}

    func didTapOutsideContent(in cell: MessageCell) {
        _ = self.sendMessageBar.inputField.resignFirstResponder()
    }

    func didTapCancelUpload(in cell: MessageCell) {
        guard let topicId = self.topicName,
            let msgIdx = self.messageSeqIdIndex[cell.seqId] else { return }
        _ = Cache.getLargeFileHelper().cancelUpload(topicId: topicId, msgId: self.messages[msgIdx].msgId)
    }

    func didEndMediaPlayback(in cell: MessageCell, audioPlayer: VLCMediaPlayer) {
        if self.currentAudioPlayer == audioPlayer {
            self.currentAudioPlayer = nil
        }
        attachmentDelegate(from: cell, action: "reset", payload: nil)
    }

    func didActivateMedia(in cell: MessageCell, audioPlayer: VLCMediaPlayer) {
        if let player = self.currentAudioPlayer, player != audioPlayer {
            player.stop()
        }
        self.currentAudioPlayer = audioPlayer
        attachmentDelegate(from: cell, action: "play", payload: nil)
    }

    func didPauseMedia(in cell: MessageCell, audioPlayer: VLCMediaPlayer) {
        if let player = self.currentAudioPlayer, player != audioPlayer {
            player.stop()
        }
        self.currentAudioPlayer = audioPlayer
        attachmentDelegate(from: cell, action: "pause", payload: nil)
    }

    func didSeekMedia(in cell: MessageCell, audioPlayer: VLCMediaPlayer, pos: Float) {
        if let player = self.currentAudioPlayer, player != audioPlayer {
            player.stop()
        }
        self.currentAudioPlayer = audioPlayer
        attachmentDelegate(from: cell, action: "seek", payload: pos)
    }

    func createPopupMenu(in cell: MessageCell) {
        guard !cell.isDeleted else { return }

        // Make cell the first responder otherwise menu will show wrong items.
        if sendMessageBar.inputField.isFirstResponder {
            sendMessageBar.inputField.nextResponderOverride = cell
        } else {
            cell.becomeFirstResponder()
        }

        // Set up the shared UIMenuController
        var menuItems: [MessageMenuItem] = []
        menuItems.append(MessageMenuItem(title: NSLocalizedString("Copy", comment: "Menu item"), action: #selector(copyMessageContent(sender:)), seqId: cell.seqId))
        if !(topic?.isChannel ?? true) {
            // Channel users cannot delete messages.
            menuItems.append(MessageMenuItem(title: NSLocalizedString("Delete", comment: "Menu item"), action: #selector(deleteMessage(sender:)), seqId: cell.seqId))
        }

        if !cell.isDeleted, let msgIndex = messageSeqIdIndex[cell.seqId], messages[msgIndex].isSynced {
            menuItems.append(MessageMenuItem(title: NSLocalizedString("Reply", comment: "Menu item"), action: #selector(showReplyPreview(sender:)), seqId: cell.seqId))
            menuItems.append(MessageMenuItem(title: NSLocalizedString("Forward", comment: "Menu item"), action: #selector(showForwardSelector(sender:)), seqId: cell.seqId))
            let msg = messages[msgIndex]
            if isFromCurrentSender(message: msg), let content = msg.content {
                // Only allow editing messages which don't contain certain entity types.
                var canEdit = true
                let prohibitedTypes: Set = ["AU", "EX", "FM", "IM", "VC", "VD"]
                for e in content.entities ?? [] {
                    if prohibitedTypes.contains(e.tp ?? "") {
                        canEdit = false
                        break
                    }
                }
                if canEdit {
                    let prohibitedStyles: Set = ["QQ"]
                    for f in content.fmt ?? [] {
                        if prohibitedStyles.contains(f.tp ?? "") {
                            canEdit = false
                            break
                        }
                    }
                }
                if canEdit {
                    menuItems.append(MessageMenuItem(title: NSLocalizedString("Edit", comment: "Menu item"), action: #selector(showEditPreview(sender:)), seqId: cell.seqId))
                }
            }
        }

        UIMenuController.shared.menuItems = menuItems

        // Show the menu.
        UIMenuController.shared.showMenu(from: cell.containerView, rect: cell.content.frame)

        // Capture menu dismissal
        NotificationCenter.default.addObserver(self, selector: #selector(willHidePopupMenu), name: UIMenuController.willHideMenuNotification, object: nil)
    }

    @objc func willHidePopupMenu() {
        if sendMessageBar.inputField.nextResponderOverride != nil {
            sendMessageBar.inputField.nextResponderOverride!.resignFirstResponder()
            sendMessageBar.inputField.nextResponderOverride = nil
        }

        UIMenuController.shared.menuItems = nil
        NotificationCenter.default.removeObserver(self, name: UIMenuController.willHideMenuNotification, object: nil)
    }

    @objc func copyMessageContent(sender: UIMenuController) {
        guard let menuItem = sender.menuItems?.first as? MessageMenuItem, menuItem.seqId > 0, let msgIndex = messageSeqIdIndex[menuItem.seqId] else { return }

        let msg = messages[msgIndex]

        var senderName: String?
        if let sub = topic?.getSubscription(for: msg.from), let pub = sub.pub {
            senderName = pub.fn
        }
        senderName = senderName ?? String(format: NSLocalizedString("Unknown %@", comment: ""), msg.from ?? "none")
        UIPasteboard.general.string = "[\(senderName!)]: \(msg.content?.string ?? ""); \(RelativeDateFormatter.shared.shortDate(from: msg.ts))"
    }

    func showInPreviewBar(content: Drafty?, forwarded: Bool, onAction action: PendingPreviewAction = .none) {
        guard let content = content else { return }
        let maxWidth = sendMessageBar.previewMaxWidth
        let maxHeight = collectionView.frame.height
        // Make sure it's properly formatted.
        let preview = (forwarded ? SendForwardedFormatter(defaultAttributes: [:]) : SendReplyFormatter(defaultAttributes: [:])).toAttributed(content, fitIn: CGSize(width: maxWidth, height: maxHeight))
        self.togglePreviewBar(with: preview, onAction: action)
    }

    @objc func showReplyPreview(sender: UIMenuController) {
        showQuotedPreview(sender: sender, isReply: true) {
            guard let value = $0, case let .replyTo(quote, _) = value else { return }
            self.showInPreviewBar(content: quote, forwarded: false, onAction: .reply)
        }
    }

    @objc func showEditPreview(sender: UIMenuController) {
        showQuotedPreview(sender: sender, isReply: false) {
            guard let value = $0, case let .edit(quote, original, _) = value else { return }
            self.sendMessageBar.inputField.becomeFirstResponder()
            self.sendMessageBar.inputField.text = original
            self.showInPreviewBar(content: quote, forwarded: false, onAction: .edit)
        }
    }

    private func showQuotedPreview(sender: UIMenuController, isReply: Bool, completion: @escaping (PendingMessage?) -> Void) {
        guard let menuItem = sender.menuItems?.first as? MessageMenuItem, menuItem.seqId > 0, let msgIndex = messageSeqIdIndex[menuItem.seqId] else { return }
        let msg = messages[msgIndex]
        if let reply = interactor?.prepareQuoted(to: msg, isReply: isReply) {
            reply.then(onSuccess: { value in
                DispatchQueue.main.async {
                    completion(value)
                }
                return nil
            }, onFailure: { err in
                DispatchQueue.main.async {
                    completion(nil)
                    UiUtils.showToast(message: "Failed to create message preview: \(err)")
                }
                return nil
            })
        }
    }

    @objc func showForwardSelector(sender: UIMenuController) {
        guard let menuItem = sender.menuItems?.first as? MessageMenuItem, menuItem.seqId > 0, let msgIndex = messageSeqIdIndex[menuItem.seqId] else { return }

        guard let msg = interactor?.createForwardedMessage(from: messages[msgIndex]) else {
            return
        }
        guard case let .forwarded(forwardedMsg, forwardedFrom, forwardedPreview) = msg else {
            return
        }
        DispatchQueue.main.async {
            let navigator = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "ForwardToNavController") as! UINavigationController
            navigator.modalPresentationStyle = .pageSheet
            let forwardToVC = navigator.viewControllers.first as! ForwardToViewController
            forwardToVC.delegate = self
            forwardToVC.forwardedContent = forwardedMsg
            forwardToVC.forwardedFrom = forwardedFrom
            forwardToVC.forwardedPreview = forwardedPreview
            self.present(navigator, animated: true, completion: nil)
        }
        return
    }

    @objc func deleteMessage(sender: UIMenuController) {
        guard let menuItem = sender.menuItems?.first as? MessageMenuItem, menuItem.seqId > 0, let index = messageSeqIdIndex[menuItem.seqId] else { return }
        let msg = messages[index]
        interactor?.deleteMessage(msg)
    }

    private func handleButtonPost(in cell: MessageCell, using url: URL) {
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String]?
        if let queryItems = parts?.queryItems {
            query = [:]
            for item in queryItems {
                query![item.name] = item.value
            }
        }
        let newMsg = Drafty(content: query?["title"] ?? NSLocalizedString("undefined", comment: "Button with missing text"))
        var json: [String: JSONValue] = [:]
        // {"seq":6,"resp":{"yes":1}}
        if let name = query?["name"], let val = query?["val"] {
            var resp: [String: JSONValue] = [:]
            resp[name] = JSONValue.string(val)
            json["resp"] = JSONValue.dict(resp)
        }
        json["seq"] = JSONValue.int(cell.seqId)

        _ = interactor?.sendMessage(content: newMsg.attachJSON(json))
    }

    static func extractAttachment(from cell: MessageCell) -> [Data]? {
        guard let text = cell.content.attributedText else { return nil }
        var parts = [Data]()

        let range = NSRange(location: 0, length: text.length)
        text.enumerateAttributes(in: range, options: NSAttributedString.EnumerationOptions(rawValue: 0)) { (object, _, _) in
            if object.keys.contains(.attachment) {
                if let attachment = object[.attachment] as? NSTextAttachment, let data = attachment.contents {
                    parts.append(data)
                }
            }
        }
        return parts
    }

    func extractEntity(from cell: MessageCell, draftyEntityKey: Int?) -> Entity? {
        guard let index = messageSeqIdIndex[cell.seqId], let draftyKey = draftyEntityKey else { return nil }
        return messages[index].content?.entities?[draftyKey]
    }

    // Call EntityTextattachmentDelegate for each text attachment in the cell.
    func attachmentDelegate(from cell: MessageCell, action: String, payload: Any?) {
        guard let text = cell.content.attributedText else { return }

        let range = NSRange(location: 0, length: text.length)
        text.enumerateAttributes(in: range, options: NSAttributedString.EnumerationOptions(rawValue: 0)) { (object, _, _) in
            if object.keys.contains(.attachment) {
                if let attachment = object[.attachment] as? EntityTextAttachment {
                    attachment.delegate?.action(action, payload: payload)
                }
            }
        }
    }

    private func handleLargeAttachment(in cell: MessageCell, using url: URL) {
        guard let data = MessageViewController.extractAttachment(from: cell), !data.isEmpty else { return }
        let downloadFrom = String(decoding: data[0], as: UTF8.self)
        guard var urlComps = URLComponents(string: downloadFrom) else { return }
        if let filename = url.extractQueryParam(named: "filename") {
            urlComps.queryItems = [URLQueryItem(name: "origfn", value: filename)]
        }
        if let targetUrl = urlComps.url, targetUrl.scheme == "http" || targetUrl.scheme == "https" {
            Cache.getLargeFileHelper().startDownload(from: targetUrl)
        }
    }

    private func handleSmallAttachment(in cell: MessageCell, using url: URL) {
        // TODO: move logic to MessageInteractor.
        guard let data = MessageViewController.extractAttachment(from: cell), !data.isEmpty else { return }
        let d = data[0]
        // FIXME: use actual mime instead of nil when generating file name.
        let filename = url.extractQueryParam(named: "filename") ?? Utils.uniqueFilename(forMime: nil)
        let documentsUrl: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsUrl.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: documentsUrl, withIntermediateDirectories: true, attributes: nil)
            try d.write(to: destinationURL)
            UiUtils.presentFileSharingVC(for: destinationURL)
        } catch {
            Cache.log.error("MessageVC - save attachment failed: %@", error.localizedDescription)
        }
    }

    private func handleToggleAudioPlay(in cell: MessageCell, draftyEntityKey key: Int?) {
        guard let entity = extractEntity(from: cell, draftyEntityKey: key) else { return }

        let duration = entity.data?["duration"]?.asInt() ?? 0
        let bits = entity.data?["val"]?.asData()
        let ref = entity.data?["ref"]?.asString()
        cell.toggleAudioPlay(url: ref, data: bits, duration: duration, key: key!)
    }

    private func handleAudioSeek(in cell: MessageCell, using url: URL) {
        let key = Int(url.extractQueryParam(named: "key") ?? "")
        guard let entity = extractEntity(from: cell, draftyEntityKey: key) else { return }

        let duration = entity.data?["duration"]?.asInt() ?? 0
        let bits = entity.data?["val"]?.asData()
        let ref = entity.data?["ref"]?.asString()
        guard let seekTo = Float(url.extractQueryParam(named: "pos") ?? "0") else { return }
        cell.audioSeekTo(seekTo, url: ref, data: bits, duration: duration, key: key!)
    }

    private func showImagePreview(in cell: MessageCell, draftyEntityKey: Int?) {
        // TODO: maybe pass nil to show "broken image" preview instead of returning.
        guard let index = messageSeqIdIndex[cell.seqId], let draftyKey = draftyEntityKey else { return }
        let msg = messages[index]
        guard let entity = msg.content?.entities?[draftyKey] else { return }
        let bits = entity.data?["val"]?.asData()
        let ref = entity.data?["ref"]?.asString()
        // Need to have at least one.
        guard bits != nil || ref != nil else { return }

        let content = ImagePreviewContent(
            imgContent: ImagePreviewContent.ImageContent.rawdata(bits, ref),
            caption: nil,
            fileName: entity.data?["name"]?.asString(),
            contentType: entity.data?["mime"]?.asString(),
            size: entity.data?["size"]?.asInt64() ?? Int64(bits?.count ?? 0),
            width: entity.data?["width"]?.asInt(),
            height: entity.data?["height"]?.asInt(),
            pendingMessagePreview: nil)
        performSegue(withIdentifier: "ShowImagePreview", sender: content)
    }

    private func showVideoPreview(in cell: MessageCell, draftyEntityKey: Int?) {
        // TODO: maybe pass nil to show "broken image" preview instead of returning.
        guard let index = messageSeqIdIndex[cell.seqId], let draftyKey = draftyEntityKey else { return }
        let msg = messages[index]
        guard let entity = msg.content?.entities?[draftyKey] else { return }
        let bits = entity.data?["val"]?.asData()
        let ref = entity.data?["ref"]?.asString()
        // Need to have either bits or ref.
        guard bits != nil || ref != nil else { return }

        let content = VideoPreviewContent(
            videoSrc: .remote(bits, ref),
            duration: entity.data?["duration"]?.asInt() ?? 0,
            fileName: entity.data?["name"]?.asString(),
            contentType: entity.data?["mime"]?.asString(),
            size: entity.data?["size"]?.asInt64() ?? 0,
            width: entity.data?["width"]?.asInt(),
            height: entity.data?["height"]?.asInt(),
            caption: nil,
            pendingMessagePreview: nil
        )

        performSegue(withIdentifier: "ShowVideoPreview", sender: content)
    }

    func handleQuoteClick(in cell: MessageCell) {
        guard let index = messageSeqIdIndex[cell.seqId] else { return }
        let msg = messages[index]
        guard let seqId = Int(msg.head?["reply"]?.asString() ?? ""), let itemIdx = messageSeqIdIndex[seqId] else { return }
        let path = IndexPath(item: itemIdx, section: 0)
        if let cell = collectionView.cellForItem(at: path) as? MessageCell {
            // If the cell is already visible.
            cell.highlightAnimated(withDuration: 4.0)
        } else {
            // Not visible? Memorize the cell and highlight it
            // after the view scrolls the cell into the viewport.
            self.highlightCellAtPathAfterScroll = path
        }
        self.collectionView.scrollToItem(at: path, at: .top, animated: true)
    }
}
