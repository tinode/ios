//
//  EditMembersViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

// TODO: refactor shared code with NewGroupVC to UiUtils.
class EditMembersViewController: UIViewController, UITableViewDataSource {
    public var topicName: String!
    private var tinode: Tinode!
    private var topic: DefaultComTopic!
    private var contactsManager = ContactsManager()
    private var contacts: [ContactHolder]!
    private var selectedContacts = [IndexPath]()
    private var initialIds = Set<String>()
    private var selectedIds = Set<String>()
    private var isAdmin: Bool = false

    @IBOutlet weak var membersTableView: UITableView!
    @IBOutlet weak var selectedCollectionView: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.membersTableView.dataSource = self
        self.membersTableView.allowsMultipleSelection = true
        self.membersTableView.delegate = self
        self.membersTableView.register(UINib(nibName: "ContactViewCell", bundle: nil), forCellReuseIdentifier: "ContactViewCell")

        self.selectedCollectionView.dataSource = self
        self.selectedCollectionView.register(UINib(nibName: "SelectedMemberViewCell", bundle: nil), forCellWithReuseIdentifier: "SelectedMemberViewCell")

        setup()
    }

    private func setup() {
        tinode = Cache.getTinode()
        topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic
        self.contacts = self.contactsManager.fetchContacts()
        let subscriptions = topic.getSubscriptions()!
        for sub in subscriptions {
            if let uid = sub.user {
                selectedIds.insert(uid)
                initialIds.insert(uid)
            }
        }
        for i in 0..<contacts.count {
            let c = contacts[i]
            if let uid = c.uniqueId, userSelected(with: uid) {
                selectedContacts.append(IndexPath(row: i, section: 0))
            }
        }
        isAdmin = topic.isAdmin
        self.navigationItem.title = topic.pub?.fn ?? "Unknown"
    }
    func addUser(with uniqueId: String) {
        self.selectedIds.insert(uniqueId)
    }
    func removeUser(with uniqueId: String) {
        self.selectedIds.remove(uniqueId)
    }
    func userSelected(with uniqueId: String) -> Bool {
        return self.selectedIds.contains(uniqueId)
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contacts.count
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ContactViewCell", for: indexPath) as! ContactViewCell

        // Configure the cell...
        let contact = contacts[indexPath.row]

        cell.avatar.set(icon: contact.image, title: contact.displayName, id: contact.uniqueId)
        cell.title.text = contact.displayName
        cell.title.sizeToFit()
        cell.subtitle.text = contact.subtitle ?? contact.uniqueId
        cell.subtitle.sizeToFit()
        cell.accessoryType = cell.isSelected ? .checkmark : .none

        // Data reload clears selection. If we already have any selected users,
        // select the corresponding rows in the table.
        if let uniqueId = contact.uniqueId, self.userSelected(with: uniqueId) {
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            cell.accessoryType = .checkmark
        }

        return cell
    }
    @IBAction func saveClicked(_ sender: Any) {
        self.updateGroup()
        self.navigationController?.popViewController(animated: true)
        self.dismiss(animated: true, completion: nil)
    }
    private func getDeltas() -> ([String], [String]) {
        let additions = selectedIds.subtracting(initialIds)
        let deletions = initialIds.subtracting(selectedIds)
        return (additions.map { $0 }, deletions.map { $0 })
    }
    func updateGroup() {
        //
        let deltas = getDeltas()
        let additions = deltas.0
        let deletions = deltas.1
        print("inviting \(additions)")
        for uid in additions {
            _ = try? topic.invite(user: uid, in: nil)?.then(
                onSuccess: nil, onFailure: UiUtils.ToastFailureHandler)
        }
        print("ejecting \(deletions)")
        for uid in deletions {
            _ = try? topic.eject(user: uid, ban: false)?.then(
                onSuccess: nil, onFailure: UiUtils.ToastFailureHandler)
        }
    }
}

extension EditMembersViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
        print("selected index path = \(indexPath)")
        let contact = contacts[indexPath.row]
        if let uniqueId = contact.uniqueId {
            self.addUser(with: uniqueId)
            selectedContacts.append(indexPath)
            selectedCollectionView.insertItems(at: [IndexPath(item: selectedContacts.count - 1, section: 0)])
        } else {
            print("no unique id for user \(contact.displayName ?? "No name")")
        }
        print("+ selected rows: \(self.selectedIds)")
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        tableView.cellForRow(at: indexPath)?.accessoryType = .none
        print("deselected index path = \(indexPath)")
        let contact = contacts[indexPath.row]
        if let uniqueId = contact.uniqueId {
            if !isAdmin && initialIds.contains(uniqueId) {
                DispatchQueue.main.async { tableView.reloadData() }
                return
            }
            self.removeUser(with: uniqueId)
            if let removeAt = selectedContacts.firstIndex(of: indexPath) {
                selectedContacts.remove(at: removeAt)
                selectedCollectionView.deleteItems(at: [IndexPath(item: removeAt, section: 0)])
            }
        } else {
            print("no unique id for user \(contact.displayName ?? "No name")")
        }
        print("- selected rows: \(self.selectedIds)")
    }
}

extension EditMembersViewController : UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        //toggleNoSelectedMembersNote(on: selectedContacts.isEmpty)
        return selectedContacts.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "SelectedMemberViewCell", for: indexPath) as! SelectedMemberViewCell
        let contact = contacts[selectedContacts[indexPath.item].item]
        cell.avatarImageView.set(icon: contact.image, title: contact.displayName, id: contact.uniqueId)
        return cell
    }
}
