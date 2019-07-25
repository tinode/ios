//
//  ChatListPresenter.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

protocol ChatListPresentationLogic {
    var underlyingViewController: UIViewController? { get }
    func presentTopics(_ topics: [DefaultComTopic], archivedTopics: [DefaultComTopic]?)
    func topicUpdated(_ name: String)
    func topicDeleted(_ name: String)
}

class ChatListPresenter: ChatListPresentationLogic {
    weak var viewController: ChatListDisplayLogic?
    var underlyingViewController: UIViewController? {
        get { return viewController as? UIViewController }
    }

    func presentTopics(_ topics: [DefaultComTopic], archivedTopics: [DefaultComTopic]?) {
        viewController?.displayChats(topics, archivedTopics: archivedTopics)
    }

    func topicUpdated(_ name: String) {
        viewController?.updateChat(name)
    }

    func topicDeleted(_ name: String) {
        viewController?.deleteChat(name)
    }
}
