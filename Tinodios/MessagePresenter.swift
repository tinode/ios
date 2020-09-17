//
//  MessagePresenter.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit

import TinodiosDB

protocol MessagePresentationLogic {
    func switchTopic(topic: String?)
    func updateTitleBar(icon: UIImage?, title: String?, online: Bool?)
    func setOnline(online: Bool?)
    func runTypingAnimation()
    func presentMessages(messages: [StoredMessage])
    func reloadMessages(fromSeqId loId: Int, toSeqId hiId: Int)
    func reloadAllMessages()
    func updateProgress(forMsgId msgId: Int64, progress: Float)
    func applyTopicPermissions(withError: Error?)
    func endRefresh()
    func dismiss()
}

class MessagePresenter: MessagePresentationLogic {
    weak var viewController: MessageDisplayLogic?

    func switchTopic(topic: String?) {
        DispatchQueue.main.async {
            self.viewController?.switchTopic(topic: topic)
        }
    }

    func updateTitleBar(icon: UIImage?, title: String?, online: Bool?) {
        DispatchQueue.main.async {
            self.viewController?.updateTitleBar(icon: icon, title: title, online: online)
        }
    }
    func setOnline(online: Bool?) {
        DispatchQueue.main.async {
            self.viewController?.setOnline(online: online)
        }
    }
    func presentMessages(messages: [StoredMessage]) {
        DispatchQueue.main.async {
            self.viewController?.displayChatMessages(messages: messages)
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
}
