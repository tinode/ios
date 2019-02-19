//
//  ContactListInteractor.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import Contacts

protocol ContactListBusinessLogic: class {
    func loadAndPresentContacts()
}

class ContactHolder {
    var displayName: String? = nil
    var imageThumbnail: Data? = nil
    var phones: [String]? = nil
    var emails: [String]? = nil
    var ims: [String]? = nil
}

class ContactListInteractor: ContactListBusinessLogic {
    static let kTinodeImProtocol = "Tinode"
    var presenter: ContactListPresentationLogic?
    var router: ContactListRoutingLogic?
    let store = CNContactStore()
    var queue = DispatchQueue(label: "co.tinode.contacts")
    private func fetchContacts() -> [ContactHolder]? {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactInstantMessageAddressesKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor
        ]
        guard let allContainers = try? store.containers(matching: nil) else {
            return nil
        }
        var contacts: [CNContact] = []
        for container in allContainers {
            let fetchPredicate =  CNContact.predicateForContactsInContainer(withIdentifier: container.identifier)
            if let containerResults = try? self.store.unifiedContacts(
                matching: fetchPredicate, keysToFetch: keysToFetch) {
                contacts.append(contentsOf: containerResults)
            }
        }
        return contacts.map {
            let systemContact = $0
            let contactHolder = ContactHolder()
            contactHolder.displayName = "\(systemContact.givenName) \(systemContact.familyName)"
            contactHolder.imageThumbnail = systemContact.imageDataAvailable ? systemContact.thumbnailImageData : nil
            contactHolder.emails = systemContact.emailAddresses.map { String($0.value) }
            contactHolder.phones = systemContact.phoneNumbers.map { String($0.value.stringValue) }
            contactHolder.ims = systemContact.instantMessageAddresses
                .filter { $0.value.service == ContactListInteractor.kTinodeImProtocol  }
                .map { $0.value.username }
            return contactHolder
        }
    }
    func loadAndPresentContacts() {
        queue.async {
            let contacts: [ContactHolder] = self.fetchContacts() ?? []
            self.presenter?.presentContacts(contacts: contacts)
        }
    }
}
