//
//  MessagePresenter.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit

protocol MessagePresentationLogic {
    func updateTitleBar(icon: UIImage?, title: String?)
    func presentMessages(messages: [StoredMessage])
    func endRefresh()
}

class MessagePresenter: MessagePresentationLogic {
    weak var viewController: MessageDisplayLogic?

    func updateTitleBar(icon: UIImage?, title: String?) {
        self.viewController?.updateTitleBar(icon: icon, title: title)
    }
    func presentMessages(messages: [StoredMessage]) {
        self.viewController?.displayChatMessages(messages: messages)
    }
    func endRefresh() {
        self.viewController?.endRefresh()
    }
}
