//
//  MessagePresenter.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

protocol MessagePresentationLogic {
    func presentMessages()
}

class MessagePresenter: MessagePresentationLogic {
    weak var viewController: MessageDisplayLogic?
    func presentMessages() {
        self.viewController?.displayChatMessages()
    }
}
