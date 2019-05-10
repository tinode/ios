//
//  FindInteractor.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

protocol FindBusinessLogic: class {
    func loadAndPresentContacts()
}

class ContactHolder {
    var displayName: String? = nil
    var image: UIImage? = nil
    var uniqueId: String? = nil

    init(displayName: String?, image: UIImage?, uniqueId: String?) {
        self.displayName = displayName
        self.image = image
        self.uniqueId = uniqueId
    }
}

class FindInteractor: FindBusinessLogic {
    static let kTinodeImProtocol = "Tinode"
    var presenter: FindPresentationLogic?
    var router: FindRoutingLogic?
    //let store = CNContactStore()
    var queue = DispatchQueue(label: "co.tinode.contacts")
    private let baseDb = BaseDb.getInstance()
    private func fetchContacts() -> [ContactHolder]? {
        guard let userDb = self.baseDb.userDb, let uid = Cache.getTinode().myUid else { return nil }
        guard let users = userDb.readAll(for: uid) else { return nil }
        // Turn users into contacts.
        return users.map { user in
            let q = user as! DefaultUser
            return ContactHolder(
                displayName: q.pub?.fn,
                image: q.pub?.photo?.image(),
                uniqueId: q.uid)
        }
    }
    func loadAndPresentContacts() {
        queue.async {
            let contacts: [ContactHolder] = self.fetchContacts() ?? []
            self.presenter?.presentContacts(contacts: contacts)
        }
    }
}
