//
//  NewGroupViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

protocol NewGroupDisplayLogic: class {
    func displayContacts(contacts: [ContactHolder])
    func presentChat(with topicName: String)
}

class NewGroupViewController: UIViewController, UITableViewDataSource {
    @IBOutlet weak var saveButtonItem: UIBarButtonItem!
    @IBOutlet weak var membersTableView: UITableView!
    @IBOutlet weak var groupNameTextField: UITextField!
    @IBOutlet weak var privateTextField: UITextField!
    @IBOutlet weak var tagsTextField: TagsEditView!
    @IBOutlet weak var avatarView: RoundImageView!
    @IBOutlet weak var selectedCollectionView: UICollectionView!

    private var contacts: [ContactHolder] = []
    private var selectedContacts: [IndexPath] = []

    private var imageUploaded: Bool = false

    private var interactor: NewGroupBusinessLogic?

    private var imagePicker: ImagePicker!

    private func setup() {
        let interactor = NewGroupInteractor()
        self.interactor = interactor
        interactor.presenter = self

        self.imagePicker = ImagePicker(presentationController: self, delegate: self)
        self.tagsTextField.onVerifyTag = { (_, tag) in
            return Utils.isValidTag(tag: tag)
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()

        self.membersTableView.dataSource = self
        self.membersTableView.allowsMultipleSelection = true
        self.membersTableView.delegate = self
        self.membersTableView.register(UINib(nibName: "ContactViewCell", bundle: nil), forCellReuseIdentifier: "ContactViewCell")

        self.selectedCollectionView.dataSource = self
        self.selectedCollectionView.register(UINib(nibName: "SelectedMemberViewCell", bundle: nil), forCellWithReuseIdentifier: "SelectedMemberViewCell")

        self.groupNameTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        self.privateTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        UiUtils.dismissKeyboardForTaps(onView: self.view)
        setup()
    }
    override func viewDidAppear(_ animated: Bool) {
        self.tabBarController?.navigationItem.rightBarButtonItem = saveButtonItem
        self.interactor?.loadAndPresentContacts()
    }
    override func viewDidDisappear(_ animated: Bool) {
        self.tabBarController?.navigationItem.rightBarButtonItem = nil
    }
    @objc func textFieldDidChange(_ textField: UITextField) {
        UiUtils.clearTextFieldError(textField)
    }
    // MARK: - Table view data source
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
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

        // Data reload clears selection. If we already have any selected users,
        // select the corresponding rows in the table.
        if let uniqueId = contact.uniqueId, self.interactor?.userSelected(with: uniqueId) ?? false {
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        }

        return cell
    }

    // MARK: - UI event handlers.
    @IBAction func loadAvatarClicked(_ sender: Any) {
        // Get avatar image
        self.imagePicker.present(from: self.view)
    }

    @IBAction func saveButtonClicked(_ sender: Any) {
        let groupName = UiUtils.ensureDataInTextField(groupNameTextField)
        // Optional
        let privateInfo = (privateTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let members = self.interactor?.selectedMembers else {
            print("members can't be empty")
            return
        }

        guard !groupName.isEmpty else { return }
        let avatar = imageUploaded ? avatarView.image?.resize(width: CGFloat(Float(UiUtils.kAvatarSize)), height: CGFloat(Float(UiUtils.kAvatarSize)), clip: true) : nil
        let tagsList = tagsTextField.tags
        self.interactor?.createGroupTopic(titled: groupName, subtitled: privateInfo, with: tagsList, consistingOf: members, withAvatar: avatar)
    }

    /// Show message that no members are selected.
    private func toggleNoSelectedMembersNote(on show: Bool) {
        if show {
            let messageLabel = UILabel(frame: CGRect(x: 0, y: 0, width: selectedCollectionView.bounds.size.width, height: selectedCollectionView.bounds.size.height))
            messageLabel.text = "No members selected"
            messageLabel.textColor = .gray
            messageLabel.numberOfLines = 0
            messageLabel.textAlignment = .center
            messageLabel.font = .preferredFont(forTextStyle: .body)
            messageLabel.sizeToFit()

            selectedCollectionView.backgroundView = messageLabel
        } else {
            selectedCollectionView.backgroundView = nil
        }
    }
}

extension NewGroupViewController: NewGroupDisplayLogic {
    func displayContacts(contacts: [ContactHolder]) {
        self.contacts = contacts
        self.membersTableView.reloadData()
    }

    func presentChat(with topicName: String) {
        self.presentChatReplacingCurrentVC(with: topicName)
    }
}

extension NewGroupViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
        print("selected index path = \(indexPath)")
        let contact = contacts[indexPath.row]
        if let uniqueId = contact.uniqueId {
            self.interactor?.addUser(with: uniqueId)
            selectedContacts.append(indexPath)
            selectedCollectionView.insertItems(at: [IndexPath(item: selectedContacts.count - 1, section: 0)])
        } else {
            print("no unique id for user \(contact.displayName ?? "No name")")
        }
        print("+ selected rows: \(self.interactor?.selectedMembers ?? [])")
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        tableView.cellForRow(at: indexPath)?.accessoryType = .none
        print("deselected index path = \(indexPath)")
        let contact = contacts[indexPath.row]
        if let uniqueId = contact.uniqueId {
            self.interactor?.removeUser(with: uniqueId)
            if let removeAt = selectedContacts.firstIndex(of: indexPath) {
                selectedContacts.remove(at: removeAt)
                selectedCollectionView.deleteItems(at: [IndexPath(item: removeAt, section: 0)])
            }
        } else {
            print("no unique id for user \(contact.displayName ?? "No name")")
        }
        print("- selected rows: \(self.interactor?.selectedMembers ?? [])")
    }
}

extension NewGroupViewController : UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        toggleNoSelectedMembersNote(on: selectedContacts.isEmpty)
        return selectedContacts.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "SelectedMemberViewCell", for: indexPath) as! SelectedMemberViewCell
        let contact = contacts[selectedContacts[indexPath.item].item]
        cell.avatarImageView.set(icon: contact.image, title: contact.displayName, id: contact.uniqueId)
        return cell
    }

}

extension NewGroupViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?, mimeType: String?, fileName: String?) {
        guard let image = image?.resize(width: CGFloat(UiUtils.kAvatarSize), height: CGFloat(UiUtils.kAvatarSize), clip: true) else {
            print("No image specified or failed to resize - skipping")
            return
        }

        self.avatarView.image = image
        imageUploaded = true
    }
}
