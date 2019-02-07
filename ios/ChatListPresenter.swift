//
//  ChatListPresenter.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

protocol ChatListPresentationLogic {
    func presentTopics(_ topics: [DefaultComTopic])
}

class ChatListPresenter: ChatListPresentationLogic {
    weak var viewController: ChatListDisplayLogic?

    func presentTopics(_ topics: [DefaultComTopic]) {
        viewController?.displayChats(topics)
    }
}
