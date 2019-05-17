//
//  FindPresenter.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

protocol FindPresentationLogic {
    func presentLocalContacts(contacts: [ContactHolder])
    func presentRemoteContacts(contacts: [ContactHolder])
}

class FindPresenter: FindPresentationLogic {
    weak var viewController: FindDisplayLogic?
    
    func presentLocalContacts(contacts: [ContactHolder]) {
        viewController?.displayLocalContacts(contacts: contacts)
    }
    func presentRemoteContacts(contacts: [ContactHolder]) {
        viewController?.displayRemoteContacts(contacts: contacts)
    }
}
