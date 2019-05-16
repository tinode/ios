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
    func setup()
    func cleanup()
    func attachToFndTopic()
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
    private class FndListener: DefaultFndTopic.Listener {
        override func onMetaSub(sub: Subscription<VCard, Array<String>>) {
            // bitmaps?
        }
        override func onSubsUpdated() {
            // reload view
        }
    }

    static let kTinodeImProtocol = "Tinode"
    static let kMinTagLength = 4
    var presenter: FindPresentationLogic?
    var router: FindRoutingLogic?
    private var queue = DispatchQueue(label: "co.tinode.contacts")
    // All known contacts from BaseDb's Users table.
    private var localContacts: [ContactHolder]?
    // Current search query (nil if none).
    private var searchQuery: String?
    private let baseDb = BaseDb.getInstance()
    private var fndTopic: DefaultFndTopic?
    private var fndListener: FindInteractor.FndListener?
    // Contacts returned by the server
    // in response to a search request.
    private var remoteContacts: [ContactHolder]?
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
    func setup() {
        fndListener = FindInteractor.FndListener()
    }
    func cleanup() {
        fndTopic?.listener = nil
        if fndTopic?.attached ?? false {
            fndTopic?.leave()
        }
    }
    func attachToFndTopic() {
        let tinode = Cache.getTinode()
        do {
            try UiUtils.attachToFndTopic(
                fndListener: self.fndListener)?.then(
                    onSuccess: { [weak self] msg in
                        self?.fndTopic = tinode.getOrCreateFndTopic()
                        return nil
                    },
                    onFailure: { err in
                        return nil
                    })
        } catch {
            print("failed to attach to fnd topic: \(error)")
        }

    }
    func loadAndPresentContacts(searchQuery: String? = nil) {
        self.searchQuery = searchQuery
        queue.async {
            if self.localContacts == nil {
                self.localContacts = self.fetchContacts() ?? []
            }
            if self.remoteContacts == nil {
               self.remoteContacts = []
            }
            let contacts: [ContactHolder] =
                self.searchQuery != nil ?
                    self.localContacts!.filter { u in
                        guard let displayName = u.displayName else { return false }
                        guard let r = displayName.range(of: self.searchQuery!, options: .caseInsensitive) else {return false}
                        return r.contains(displayName.startIndex)
                    } :
                    self.localContacts!
            if let queryString = searchQuery, queryString.count >= FindInteractor.kMinTagLength {
                /*
                let tinode = Cache.getTinode()
                let metaDesc: MetaSetDesc<String, String> = MetaSetDesc(pub: queryString, priv: nil)
                let setMeta: MsgSetMeta<String, String> = MsgSetMeta<String, String>(
                    desc: metaDesc, sub: nil, tags: nil)
                */
                self.remoteContacts?.removeAll()
            } else {
                // Clear remoteContacts.
                self.remoteContacts?.removeAll()
            }
            self.presenter?.presentContacts(contacts: contacts)
        }
    }
}
