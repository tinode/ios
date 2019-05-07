//
//  FindPresenter.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

protocol FindPresentationLogic {
    func presentContacts(contacts: [ContactHolder])
}

class FindPresenter: FindPresentationLogic {
    weak var viewController: FindDisplayLogic?
    
    func presentContacts(contacts: [ContactHolder]) {
        viewController?.displayContacts(contacts: contacts)
    }
}
