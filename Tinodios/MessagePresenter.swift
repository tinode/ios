//
//  MessagePresenter.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit

protocol MessagePresentationLogic {
    var underlyingViewController: UIViewController? { get }
    func updateTitleBar(icon: UIImage?, title: String?, online: Bool)
    func setOnline(online: Bool)
    func runTypingAnimation()
    func presentMessages(messages: [StoredMessage])
    func reloadMessage(withSeqId seqId: Int)
    func updateProgress(forMsgId msgId: Int64, progress: Float)
    func applyTopicPermissions()
    func endRefresh()
    func dismiss()
}

class MessagePresenter: MessagePresentationLogic {
    weak var viewController: MessageDisplayLogic?

    var underlyingViewController: UIViewController? {
        get { return viewController as? UIViewController }
    }

    func updateTitleBar(icon: UIImage?, title: String?, online: Bool) {
        self.viewController?.updateTitleBar(icon: icon, title: title, online: online)
    }
    func setOnline(online: Bool) {
        self.viewController?.setOnline(online: online)
    }
    func presentMessages(messages: [StoredMessage]) {
        self.viewController?.displayChatMessages(messages: messages)
    }
    func reloadMessage(withSeqId seqId: Int) {
        self.viewController?.reloadMessage(withSeqId: seqId)
    }
    func updateProgress(forMsgId msgId: Int64, progress: Float) {
        self.viewController?.updateProcess(forMsgId: msgId, progress: progress)
    }
    func endRefresh() {
        self.viewController?.endRefresh()
    }
    func runTypingAnimation() {
        self.viewController?.runTypingAnimation()
    }
    func applyTopicPermissions() {
        self.viewController?.applyTopicPermissions()
    }
    func dismiss() {
        self.viewController?.dismiss()
    }
}
