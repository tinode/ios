//
//  MessagePresenter.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit

protocol MessagePresentationLogic {
    func updateTitleBar(icon: UIImage?, title: String?, online: Bool)
    func setOnline(online: Bool)
    func runTypingAnimation()
    func presentMessages(messages: [StoredMessage])
    func endRefresh()
}

class MessagePresenter: MessagePresentationLogic {
    weak var viewController: MessageDisplayLogic?

    func updateTitleBar(icon: UIImage?, title: String?, online: Bool) {
        self.viewController?.updateTitleBar(icon: icon, title: title, online: online)
    }
    func setOnline(online: Bool) {
        self.viewController?.setOnline(online: online)
    }
    func presentMessages(messages: [StoredMessage]) {
        self.viewController?.displayChatMessages(messages: messages)
    }
    func endRefresh() {
        self.viewController?.endRefresh()
    }
    func runTypingAnimation() {
        self.viewController?.runTypingAnimation()
    }
}
