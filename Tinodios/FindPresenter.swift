//
//  FindPresenter.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

protocol FindPresentationLogic {
    var viewController: FindDisplayLogic? { get set }
    func presentLocalContacts(contacts: [ContactHolder])
    func presentRemoteContacts(contacts: [RemoteContactHolder])
}

class FindPresenter: FindPresentationLogic {
    weak var viewController: FindDisplayLogic?

    func presentLocalContacts(contacts: [ContactHolder]) {
        DispatchQueue.main.async {
            self.viewController?.displayLocalContacts(contacts: contacts)
        }
    }
    func presentRemoteContacts(contacts: [RemoteContactHolder]) {
        DispatchQueue.main.async {
            self.viewController?.displayRemoteContacts(contacts: contacts)
        }
    }
}
