//
//  ContactListRouter.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit

protocol ContactListRoutingLogic {
    func routeToContact(segue: UIStoryboardSegue)
}

class ContactListRouter: ContactListRoutingLogic {
    weak var viewController: ContactListViewController?
    
    func routeToContact(segue: UIStoryboardSegue) {
        // TODO: implmenent.
    }
}
