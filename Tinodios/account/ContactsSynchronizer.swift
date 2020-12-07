//
//  ContactsSynchronizer.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import Contacts
import TinodeSDK
import TinodiosDB

class ContactsSynchronizer {
    private class ContactHolder2 {
        var displayName: String? = nil
        var imageThumbnail: Data? = nil
        var phones: [String]? = nil
        var emails: [String]? = nil

        func toString() -> String {
            var vals = [String]()
            if let phones = self.phones {
                vals += phones
            }
            if let emails = self.emails {
                vals += emails
            }
            return vals.joined(separator: ",")
        }
    }
    public static let `default` = ContactsSynchronizer()
    private let store = CNContactStore()
    private let queue = DispatchQueue(label: "co.tinode.sync")
    public var authStatus: CNAuthorizationStatus = .notDetermined {
        didSet {
            if self.authStatus == .authorized {
                permissionsChangedCallback?(self.authStatus)
                queue.async {
                    self.synchronizeInternal()
                }
            }
        }
    }
    private static let kTinodeServerSyncMarker = "tinodeServerSyncMarker"
    private var serverSyncMarker: Date? {
        get {
            return SharedUtils.kAppDefaults.object(
                forKey: ContactsSynchronizer.kTinodeServerSyncMarker) as? Date
        }
        set {
            if let v = newValue {
                SharedUtils.kAppDefaults.set(
                    v, forKey: ContactsSynchronizer.kTinodeServerSyncMarker)
            }
        }
    }
    public var permissionsChangedCallback: ((CNAuthorizationStatus) -> Void)?

    public init() {
        // Watch contact book changes.
        NotificationCenter.default.addObserver(
                self, selector: #selector(contactStoreDidChange), name: .CNContactStoreDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.appBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
    }

    @objc func contactStoreDidChange(notification: NSNotification) {
        Cache.log.info("Contact change: notification %@", notification)
        self.run()
    }

    @objc
    func appBecameActive() {
        if self.authStatus == .authorized {
            self.run()
        } else {
            Cache.log.debug("Can't perform contact sync: unauthorized")
        }
    }

    private func fetchContacts() -> [ContactHolder2]? {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor
        ]
        var contacts = [CNContact]()
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        do {
            try self.store.enumerateContacts(with: request) {
                (contact, cursor) -> Void in
                contacts.append(contact)
            }
        } catch let error {
            Cache.log.error("ContactsSynchronizer - system contact fetch error: %@", error.localizedDescription)
        }

        return contacts.map {
            let systemContact = $0
            let contactHolder = ContactHolder2()
            contactHolder.displayName = "\(systemContact.givenName) \(systemContact.familyName)"
            contactHolder.imageThumbnail = systemContact.imageDataAvailable ? systemContact.thumbnailImageData : nil
            contactHolder.emails = systemContact.emailAddresses.map { String($0.value) }
            contactHolder.phones = systemContact.phoneNumbers.map { $0.value.naiveE164 }
            return contactHolder
        }
    }
    func run() {
        switch self.authStatus {
        case .notDetermined:
            self.store.requestAccess(for: .contacts,
                                     completionHandler: { [weak self] (granted, error) in
                if granted {
                    // This will trigger synchronizeInternal.
                    self?.authStatus = .authorized
                } else {
                    Cache.log.error("ContactsSynchronizer - permissions denied.")
                    self?.authStatus = .denied
                }
            })
        case .authorized:
            self.queue.async {
                self.synchronizeInternal()
            }
        default:
            Cache.log.info("ContactsSynchronizer - not authorized to access contacts. quitting...")
            break
        }
    }
    private func contactsToQueryString(contacts: [ContactHolder2]) -> String {
        return contacts.map { $0.toString() }.joined(separator: ",")
    }
    private func synchronizeInternal() {
        var success = false
        let contactsManager = ContactsManager.default
        let t0 = SharedUtils.getAuthToken()
        if let token = t0, !token.isEmpty, let contacts = self.fetchContacts(), !contacts.isEmpty {
            Cache.log.info("ContactsSynchronizer - starting sync.")
            let contacts: String = contactsToQueryString(contacts: contacts)
            var lastSyncMarker = self.serverSyncMarker
            let tinode = Cache.tinode
            do {
                tinode.setAutoLoginWithToken(token: token)
                _ = try tinode.connectDefault(inBackground: true)?.getResult()

                _ = try tinode.loginToken(token: token, creds: nil).getResult()
                // Generic params don't matter.
                _ = try tinode.subscribe(to: Tinode.kTopicFnd, set: MsgSetMeta<Int, Int>?(nil), get: nil).getResult()
                let metaDesc: MetaSetDesc<Int, String> = MetaSetDesc(pub: nil, priv: contacts)
                let setMeta: MsgSetMeta<Int, String> = MsgSetMeta<Int, String>(desc: metaDesc, sub: nil, tags: nil, cred: nil)
                _ = try tinode.setMeta(for: Tinode.kTopicFnd, meta: setMeta).getResult()
                let meta = MsgGetMeta(desc: nil, sub: MetaGetSub(user: nil, ims: lastSyncMarker, limit: nil), data: nil, del: nil, tags: false, cred: false)
                let future = tinode.getMeta(topic: Tinode.kTopicFnd, query: meta)
                if try future.waitResult() {
                    let pkt = try! future.getResult()
                    guard let subs = pkt?.meta?.sub else { return }
                    for sub in subs {
                        if Tinode.topicTypeByName(name: sub.user) == .p2p {
                            if (lastSyncMarker ?? Date.distantPast) < (sub.updated ?? Date.distantPast) {
                                lastSyncMarker = sub.updated
                            }
                            contactsManager.processSubscription(sub: sub)
                        }
                    }
                    if lastSyncMarker != nil {
                        serverSyncMarker = lastSyncMarker
                    }
                }

                success = true
            } catch {
                Cache.log.error("ContactsSynchronizer - sync failure: %@", error.localizedDescription)
            }
            Cache.log.info("ContactsSynchronizer - sync operation completed: %@", (success ? "success" : "failure"))
        }
    }
}

extension CNPhoneNumber {
    // Hack: simply filters out all non-digit characters.
    var naiveE164: String {
        return self.value(forKey: "unformattedInternationalStringValue") as? String ?? ""
    }
}
