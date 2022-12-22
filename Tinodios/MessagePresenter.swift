//
//  MessagePresenter.swift
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

protocol MessagePresentationLogic {
    func switchTopic(topic: String?)
    func updateTitleBar(pub: TheCard?, online: Bool?, deleted: Bool)
    func setOnline(online: Bool?)
    func runTypingAnimation()
    func presentMessages(messages: [StoredMessage], _ scrollToMostRecentMessage: Bool)
    func reloadMessages(fromSeqId loId: Int, toSeqId hiId: Int)
    func reloadAllMessages()
    func updateProgress(forMsgId msgId: Int64, progress: Float)
    func applyTopicPermissions(withError: Error?)
    func endRefresh()
    func dismiss()
    func dismissPendingMessagePreviewBar()
    func clearInputField()
}

class MessagePresenter: MessagePresentationLogic {
    weak var viewController: MessageDisplayLogic?

    func switchTopic(topic: String?) {
        DispatchQueue.main.async {
            self.viewController?.switchTopic(topic: topic)
        }
    }

    func updateTitleBar(pub: TheCard?, online: Bool?, deleted: Bool) {
        DispatchQueue.main.async {
            self.viewController?.updateTitleBar(pub: pub, online: online, deleted: deleted)
        }
    }
    func setOnline(online: Bool?) {
        DispatchQueue.main.async {
            self.viewController?.setOnline(online: online)
        }
    }
    func presentMessages(messages: [StoredMessage], _ scrollToMostRecentMessage: Bool) {
        DispatchQueue.main.async {
            self.viewController?.displayChatMessages(messages: messages, scrollToMostRecentMessage)
        }
    }
    func reloadMessages(fromSeqId loId: Int, toSeqId hiId: Int) {
        DispatchQueue.main.async {
            self.viewController?.reloadMessages(fromSeqId: loId, toSeqId: hiId)
        }
    }
    func reloadAllMessages() {
        DispatchQueue.main.async {
            self.viewController?.reloadAllMessages()
        }
    }
    func updateProgress(forMsgId msgId: Int64, progress: Float) {
        DispatchQueue.main.async {
            self.viewController?.updateProgress(forMsgId: msgId, progress: progress)
        }
    }
    func endRefresh() {
        DispatchQueue.main.async {
            self.viewController?.endRefresh()
        }
    }
    func runTypingAnimation() {
        DispatchQueue.main.async {
            self.viewController?.runTypingAnimation()
        }
    }
    func applyTopicPermissions(withError err: Error? = nil) {
        DispatchQueue.main.async {
            self.viewController?.applyTopicPermissions(withError: err)
        }
    }
    func dismiss() {
        DispatchQueue.main.async {
            self.viewController?.dismissVC()
        }
    }
    func dismissPendingMessagePreviewBar() {
        DispatchQueue.main.async {
            self.viewController?.togglePreviewBar(with: nil, onAction: .none)
        }
    }

    private func clearInput() {
        (self.viewController as? MessageViewController)?.sendMessageBar.inputField.text = nil
    }

    func clearInputField() {
        if Thread.isMainThread {
            // We are on main thread. Clear synchronously.
            clearInput()
            return
        }
        DispatchQueue.main.async {
            self.clearInput()
        }
    }
}
