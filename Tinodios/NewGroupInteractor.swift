//
//  NewGroupInteractor.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit
import TinodeSDK

protocol NewGroupBusinessLogic: class {
    var selectedMembers: Array<String> { get }
    func loadAndPresentContacts()
    func addUser(with uniqueId: String)
    func removeUser(with uniqueId: String)
    func createGroupTopic(
        titled name: String, subtitled subtitle: String,
        with tags: [String]?, consistingOf members: [String],
        withAvatar avatar: UIImage?)
}

class NewGroupInteractor: NewGroupBusinessLogic {
    private var contacts: [ContactHolder]?
    private var contactsManager = ContactsManager()
    var selectedUsers = Set<String>()
    var selectedMembers: Array<String> {
        get {
            return selectedUsers.map { $0 }
        }
    }
    weak var presenter: NewGroupDisplayLogic?
    func loadAndPresentContacts() {
        self.contacts = self.contactsManager.fetchContacts()
        self.presenter?.displayContacts(contacts: contacts ?? [])
    }
    func addUser(with uniqueId: String) {
        self.selectedUsers.insert(uniqueId)
    }
    func removeUser(with uniqueId: String) {
        self.selectedUsers.remove(uniqueId)
    }
    func createGroupTopic(titled name: String, subtitled subtitle: String, with tags: [String]?, consistingOf members: [String], withAvatar avatar: UIImage?) {
        let tinode = Cache.getTinode()
        let topic = DefaultComTopic(in: tinode, forwardingEventsTo: nil)
        topic.pub = VCard(fn: name, avatar: avatar)
        topic.priv = ["comment": .string(!subtitle.isEmpty ? subtitle : Tinode.kNullValue)]
        topic.tags = tags
        do {
            try topic.subscribe()?.then(
                onSuccess: { msg in
                    // TODO: invite members
                    // route to chat
                    self.presenter?.presentChat(with: topic.name)
                    return nil
                },
                onFailure: { err in
                    print("error in \(err)")
                    return nil
                })
        } catch {
            print("failed to create group: \(error)")
        }
    }
}
