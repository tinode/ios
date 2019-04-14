//
//  FindRouter.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit

protocol FindRoutingLogic {
    func routeToContact(segue: UIStoryboardSegue)
}

class FindRouter: FindRoutingLogic {
    weak var viewController: FindViewController?
    
    func routeToContact(segue: UIStoryboardSegue) {
        // TODO: implmenent.
    }
}
