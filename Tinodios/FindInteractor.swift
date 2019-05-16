//
//  FindInteractor.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

protocol FindBusinessLogic: class {
    func loadAndPresentContacts(searchQuery: String?)
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
    var queue = DispatchQueue(label: "co.tinode.contacts")
    // All known contacts from BaseDb's Users table.
    var allContacts: [ContactHolder]?
    // Current search query (nil if none).
    var searchQuery: String?
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
    func loadAndPresentContacts(searchQuery: String? = nil) {
        self.searchQuery = searchQuery
        queue.async {
            if self.allContacts == nil {
                self.allContacts = self.fetchContacts() ?? []
            }
            let contacts: [ContactHolder] =
                self.searchQuery != nil ?
                    self.allContacts!.filter { u in
                        guard let displayName = u.displayName else { return false }
                        guard let r = displayName.range(of: self.searchQuery!, options: .caseInsensitive) else {return false}
                        return r.contains(displayName.startIndex)
                    } :
                    self.allContacts!
            self.presenter?.presentContacts(contacts: contacts)
        }
    }
}
