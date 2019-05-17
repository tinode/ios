//
//  FindInteractor.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

protocol FindBusinessLogic: class {
    var fndTopic: DefaultFndTopic? { get }
    func loadAndPresentContacts(searchQuery: String?)
    func updateAndPresentRemoteContacts()
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
        weak var interactor: FindBusinessLogic?
        override func onMetaSub(sub: Subscription<VCard, Array<String>>) {
            // bitmaps?
        }
        override func onSubsUpdated() {
            self.interactor?.updateAndPresentRemoteContacts()
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
    var fndTopic: DefaultFndTopic?
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
        fndListener?.interactor = self
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
    func updateAndPresentRemoteContacts() {
        if let subs = fndTopic?.getSubscriptions() {
            self.remoteContacts = subs.map { sub in
                return ContactHolder(displayName: sub.pub?.fn, image: nil, uniqueId: sub.uniqueId)
            }
        } else {
            self.remoteContacts?.removeAll()
        }
        self.presenter?.presentRemoteContacts(contacts: self.remoteContacts!)
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
                self.fndTopic?.setMeta(
                    meta: MsgSetMeta(desc: MetaSetDesc(pub: queryString, priv: nil),
                    sub: nil, tags: nil))
                self.fndTopic?.getMeta(query: MsgGetMeta.sub())

                self.remoteContacts?.removeAll()
            }/* else {
                // Clear remoteContacts.
                self.remoteContacts?.removeAll()
            }*/
            self.presenter?.presentLocalContacts(contacts: contacts)
        }
    }
}
