//
//  ContactListPresenter.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

protocol ContactListPresentationLogic {
    func presentContacts(contacts: [ContactHolder])
}

class ContactListPresenter: ContactListPresentationLogic {
    weak var viewController: ContactListDisplayLogic?
    
    func presentContacts(contacts: [ContactHolder]) {
        viewController?.displayContacts(contacts: contacts)
    }
}
