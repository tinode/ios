//
//  NewChatTabController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

class NewChatTabController: UITabBarController, UITabBarControllerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        self.delegate = self
    }

    func tabBarController(_ tabBarController: UITabBarController,
                          shouldSelect viewController: UIViewController) -> Bool {
        guard let viewControllers = self.viewControllers else { return false }
        guard viewControllers[selectedIndex] !== viewController else { return false }
        for controller in viewControllers.compactMap({ $0 as? FindViewController }) {
            controller.cancelPendingSearchRequest(deactivateSearch: true)
        }
        return true
    }
}
