//
//  ChatListRouter.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

protocol ChatListRoutingLogic {
    func routeToChat(segue: UIStoryboardSegue)
    func routeToLogin()
}

class ChatListRouter: ChatListRoutingLogic {
    weak var viewController: ChatListViewController?

    func routeToChat(segue: UIStoryboardSegue) {
        // TODO: implmenent.
    }
    func routeToLogin() {
        self.viewController?.displayLoginView()
    }
}
