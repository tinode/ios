//
//  FindRouter.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit

protocol FindRoutingLogic {
    func routeToChat(segue: UIStoryboardSegue)
}

class FindRouter: FindRoutingLogic {
    weak var viewController: FindViewController?
    
    func routeToChat(segue: UIStoryboardSegue) {
        if let indexPath = viewController?.tableView.indexPathForSelectedRow,
            let uniqueId = viewController?.contacts[indexPath.row].uniqueId, !uniqueId.isEmpty {
            // TODO: replace Find VC instead of pushing it on the stack.
            let messageController = segue.destination as! MessageViewController
            messageController.topicName = uniqueId
        }
    }
}
