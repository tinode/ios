//
//  NewGroupInteractor.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

protocol NewGroupBusinessLogic: class {
    func loadAndPresentContacts()
}

class NewGroupInteractor: NewGroupBusinessLogic {
    private var contacts: [ContactHolder]?
    private var contactsManager = ContactsManager()
    weak var presenter: NewGroupDisplayLogic?
    func loadAndPresentContacts() {
        self.contacts = self.contactsManager.fetchContacts()
        self.presenter?.displayContacts(contacts: contacts ?? [])
    }
}
