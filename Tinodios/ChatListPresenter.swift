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
    func topicUpdated(_ name: String)
    func topicDeleted(_ name: String)
}

class ChatListPresenter: ChatListPresentationLogic {
    weak var viewController: ChatListDisplayLogic?

    func presentTopics(_ topics: [DefaultComTopic]) {
        viewController?.displayChats(topics)
    }

    func topicUpdated(_ name: String) {
        viewController?.updateChat(name)
    }

    func topicDeleted(_ name: String) {
        viewController?.deleteChat(name)
    }
}
