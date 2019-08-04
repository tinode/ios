//
//  ContactsSynchronizer.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import Contacts
import TinodeSDK

class ContactsSynchronizer {
    private class ContactHolder2 {
        var displayName: String? = nil
        var imageThumbnail: Data? = nil
        var phones: [String]? = nil
        var emails: [String]? = nil
        var ims: [String]? = nil

        public static let kPhoneLabel = "tel:"
        public static let kEmailLabel = "email:"
        public static let kTinodeLabel = "tinode:"

        func toString() -> String {
            var vals = [String]()
            if let phones = self.phones {
                vals += phones.map { ContactHolder2.kPhoneLabel + $0 }
            }
            if let emails = self.emails {
                vals += emails.map { ContactHolder2.kEmailLabel + $0 }
            }
            if let ims = self.ims {
                vals += ims.map { ContactHolder2.kTinodeLabel + $0 }
            }
            return vals.joined(separator: ",")
        }
    }
    public static let `default` = ContactsSynchronizer()
    private let store = CNContactStore()
    private let queue = DispatchQueue(label: "co.tinode.sync")
    private var authStatus: CNAuthorizationStatus = .notDetermined {
        didSet {
            if self.authStatus == .authorized {
                queue.async {
                    self.synchronizeInternal()
                }
            }
        }
    }
    private static let kTinodeServerSyncMarker = "tinodeServerSyncMarker"
    private var serverSyncMarker: Date? {
        get {
            let userDefaults = UserDefaults.standard
            return userDefaults.object(
                forKey: ContactsSynchronizer.kTinodeServerSyncMarker) as? Date
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(
                    v, forKey: ContactsSynchronizer.kTinodeServerSyncMarker)
            }
        }
    }

    private func fetchContacts() -> [ContactHolder2]? {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactInstantMessageAddressesKey as CNKeyDescriptor,
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
            print("Fetch contact error: \(error)")
        }

        return contacts.map {
            let systemContact = $0
            let contactHolder = ContactHolder2()
            contactHolder.displayName = "\(systemContact.givenName) \(systemContact.familyName)"
            contactHolder.imageThumbnail = systemContact.imageDataAvailable ? systemContact.thumbnailImageData : nil
            contactHolder.emails = systemContact.emailAddresses.map { String($0.value) }
            contactHolder.phones = systemContact.phoneNumbers.map { $0.value.naiveE164 }
            contactHolder.ims = systemContact.instantMessageAddresses
                .filter { $0.value.service == FindInteractor.kTinodeImProtocol  }
                .map { $0.value.username }
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
                    NSLog("Permission denied")
                    self?.authStatus = .denied
                }
            })
        case .authorized:
            self.queue.async {
                self.synchronizeInternal()
            }
        default:
            print("not authorized to access contacts. quitting...")
            break
        }
    }
    private func contactsToQueryString(contacts: [ContactHolder2]) -> String {
        return contacts.map { $0.toString() }.joined(separator: ",")
    }
    private func synchronizeInternal() {
        var success = false
        let contactsManager = ContactsManager.default
        let t0 = Utils.getAuthToken()
        if let token = t0, !token.isEmpty, let contacts = self.fetchContacts(), !contacts.isEmpty {
            print("starting sync for account")
            let contacts: String = contactsToQueryString(contacts: contacts)
            var lastSyncMarker = self.serverSyncMarker
            let tinode = Cache.getTinode()
            do {
                let (hostName, useTLS, _) = SettingsHelper.getConnectionSettings()
                // TODO: implement TLS.
                tinode.setAutoLoginWithToken(token: token)
                _ = try tinode.connect(to: (hostName ?? Cache.kHostName), useTLS: (useTLS ?? false))?.getResult()

                _ = try tinode.loginToken(token: token, creds: nil)?.getResult()
                // Generic params don't matter.
                _ = try tinode.subscribe(to: Tinode.kTopicFnd, set: MsgSetMeta<Int, Int>?(nil), get: nil)?.getResult()
                //let q: Int? = nil
                let metaDesc: MetaSetDesc<Int, String> = MetaSetDesc(pub: nil, priv: contacts)
                let setMeta: MsgSetMeta<Int, String> = MsgSetMeta<Int, String>(
                    desc: metaDesc, sub: nil, tags: nil, cred: nil)
                _ = try tinode.setMeta(
                    for: Tinode.kTopicFnd,
                    meta: setMeta)?.getResult()
                let meta = MsgGetMeta(
                    desc: nil,
                    sub: MetaGetSub(user: nil, ims: lastSyncMarker, limit: nil),
                    data: nil, del: nil, tags: false)
                if let future = tinode.getMeta(topic: Tinode.kTopicFnd, query: meta) {
                    if try future.waitResult() {
                        print("okay")
                        let pkt = try! future.getResult()
                        guard let subs = pkt?.meta?.sub else { return }
                        print("got subs\nquery = \(contacts)\nsubs = \(subs)")
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
                }
                success = true
            } catch {
                print("Failed to connect to synchronize contacts: \(error)")
            }
            print("Contact sync operation completed: " +
                (success ? "success" : "failure"))
        }
    }
}

extension CNPhoneNumber {
    // Hack: simply filters out all non-digit characters.
    var naiveE164: String {
        get {
            return self.value(forKey: "unformattedInternationalStringValue") as? String ?? ""
        }
    }
}
