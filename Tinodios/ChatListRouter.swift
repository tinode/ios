//
//  ChatListRouter.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

protocol ChatListRoutingLogic {
    func routeToChat(withName name: String, for segue: UIStoryboardSegue)
    func routeToLogin()
}

class ChatListRouter: ChatListRoutingLogic {
    weak var viewController: ChatListViewController?

    func routeToChat(withName name: String, for segue: UIStoryboardSegue) {
        let messageController = segue.destination as! MessageViewController
        messageController.topicName = name
        /*
        if let indexPath = viewController?.tableView.indexPathForSelectedRow {
            let messageController = segue.destination as! MessageViewController
            messageController.topicName = viewController?.topics[indexPath.row].name
        }
        */
    }
    func routeToLogin() {
        self.viewController?.displayLoginView()
    }
}
