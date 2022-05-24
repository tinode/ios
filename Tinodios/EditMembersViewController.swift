//
//  EditMembersViewController.swift
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK

public protocol EditMembersDelegate: AnyObject {
    // Asks for the UIDs and contact info of initially selected members
    func editMembersInitialSelection(_: UIView) -> [ContactHolder]
    // Called when the editor completes selection.
    func editMembersDidEndEditing(_: UIView, added: [String], removed: [String])
    // Called when member is added or removed. Return 'true' to continue, 'false' to reject the change.
    func editMembersWillChangeState(_: UIView, uid: String, added: Bool, initiallySelected: Bool) -> Bool
}

class EditMembersViewController: UIViewController, UITableViewDataSource {
    private var contactsManager = ContactsManager()
    private var contacts: [ContactHolder]!
    private var selectedContacts = [IndexPath]()
    private var initialIds = Set<String>()
    private var selectedIds = Set<String>()

    weak var delegate: EditMembersDelegate?

    @IBOutlet var editMembersView: UIView!
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
        var uid2contact = [String: Int]()
        let subscriptions = delegate?.editMembersInitialSelection(editMembersView)
        if let subs = subscriptions {
            for (idx, contact) in subs.enumerated() {
                if let uid = contact.uniqueId {
                    selectedIds.insert(uid)
                    initialIds.insert(uid)
                    uid2contact[uid] = idx
                }
            }
        }

        var presentIds = Set<String>()
        contacts = contactsManager.fetchContacts()
        for i in 0..<contacts.count {
            let c = contacts[i]
            if let uid = c.uniqueId, userSelected(with: uid) {
                selectedContacts.append(IndexPath(row: i, section: 0))
                presentIds.insert(uid)
            }
        }
        let unknownIds = initialIds.subtracting(presentIds)
        for uid in unknownIds {
            if let idx = uid2contact[uid], let c = subscriptions?[idx] {
                contacts.append(c)
                selectedContacts.append(IndexPath(row: contacts.count - 1, section: 0))
            }
        }
        self.navigationItem.title = NSLocalizedString("Manage members", comment: "View title")
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

        cell.avatar.set(pub: contact.pub, id: contact.uniqueId, deleted: false)
        cell.title.text = contact.pub?.fn
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
        navigationController?.popViewController(animated: true)

        let deltas = getDeltas()
        let additions = deltas.0
        let deletions = deltas.1

        delegate?.editMembersDidEndEditing(editMembersView, added: additions, removed: deletions)

        dismiss(animated: true, completion: nil)
    }

    @IBAction func cancelClicked(_ sender: Any) {
        self.navigationController?.popViewController(animated: true)
        self.dismiss(animated: true, completion: nil)
    }

    private func getDeltas() -> ([String], [String]) {
        let additions = selectedIds.subtracting(initialIds)
        let deletions = initialIds.subtracting(selectedIds)
        return (additions.map { $0 }, deletions.map { $0 })
    }
}

extension EditMembersViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let uid = contacts[indexPath.row].uniqueId else {
            Cache.log.debug("EditMembersVC - no unique id for user at %d", indexPath.row)
            return nil
        }

        return delegate?.editMembersWillChangeState(editMembersView, uid: uid, added: true, initiallySelected: initialIds.contains(uid)) ?? true ? indexPath : nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let uid = contacts[indexPath.row].uniqueId else {
            Cache.log.debug("EditMembersVC - no unique id for user at %d", indexPath.row)
            return
        }

        tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
        self.addUser(with: uid)
        selectedContacts.append(indexPath)
        selectedCollectionView.insertItems(at: [IndexPath(item: selectedContacts.count - 1, section: 0)])
    }

    func tableView(_ tableView: UITableView, willDeselectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let uid = contacts[indexPath.row].uniqueId else {
            Cache.log.debug("EditMembersVC - no unique id for user at %d", indexPath.row)
            return indexPath
        }

        return delegate?.editMembersWillChangeState(editMembersView, uid: uid, added: false, initiallySelected: initialIds.contains(uid)) ?? true ? indexPath : nil
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard let uid = contacts[indexPath.row].uniqueId else {
            Cache.log.debug("EditMembersVC - no unique id for user at %d", indexPath.row)
            return
        }

        tableView.cellForRow(at: indexPath)?.accessoryType = .none
        self.removeUser(with: uid)
        if let removeAt = selectedContacts.firstIndex(of: indexPath) {
            selectedContacts.remove(at: removeAt)
            selectedCollectionView.deleteItems(at: [IndexPath(item: removeAt, section: 0)])
        }
    }
}

extension EditMembersViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // toggleNoSelectedMembersNote(on: selectedContacts.isEmpty)
        return selectedContacts.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "SelectedMemberViewCell", for: indexPath) as! SelectedMemberViewCell
        let contact = contacts[selectedContacts[indexPath.item].item]
        cell.avatarImageView.set(pub: contact.pub, id: contact.uniqueId, deleted: false)
        return cell
    }
}
