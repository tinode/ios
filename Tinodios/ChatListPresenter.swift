//
//  ChatListPresenter.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

protocol ChatListPresentationLogic {
    func presentTopics(_ topics: [DefaultComTopic])
    func updateChat(_ name: String)
}

class ChatListPresenter: ChatListPresentationLogic {
    weak var viewController: ChatListDisplayLogic?

    func presentTopics(_ topics: [DefaultComTopic]) {
        viewController?.displayChats(topics)
    }

    func updateChat(_ name: String) {
        viewController?.updateChat(name)
    }
}
