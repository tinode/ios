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
    @IBOutlet weak var tagsTextField: UITextField!
    @IBOutlet weak var avatarView: RoundImageView!

    private var contacts = [ContactHolder]()
    private var interactor: NewGroupBusinessLogic?

    private var imagePicker: ImagePicker!

    private func setup() {
        let interactor = NewGroupInteractor()
        self.interactor = interactor
        interactor.presenter = self

        self.imagePicker = ImagePicker(presentationController: self, delegate: self)
    }
    override func viewDidLoad() {
        super.viewDidLoad()

        self.membersTableView.dataSource = self
        self.membersTableView.allowsMultipleSelection = true
        self.membersTableView.delegate = self

        self.groupNameTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        self.privateTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        self.tagsTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "NewGroupTableViewCell", for: indexPath)

        // Configure the cell...
        let contact = contacts[indexPath.row]
        cell.textLabel?.text = contact.displayName
        cell.detailTextLabel?.text = contact.uniqueId

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
        let privateInfo = UiUtils.ensureDataInTextField(privateTextField)
        let tags = UiUtils.ensureDataInTextField(tagsTextField)
        guard let members = self.interactor?.selectedMembers else {
            print("members can't be empty")
            return
        }
        guard !groupName.isEmpty && !privateInfo.isEmpty && !tags.isEmpty else { return }
        let avatar = avatarView.image?.resize(width: CGFloat(Float(UiUtils.kAvatarSize)), height: CGFloat(Float(UiUtils.kAvatarSize)), clip: true)
        let tagsList = Utils.parseTags(from: tags)
        self.interactor?.createGroupTopic(titled: groupName, subtitled: privateInfo, with: tagsList, consistingOf: members, withAvatar: avatar)
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
        print("selected index path = \(indexPath)")
        let contact = contacts[indexPath.row]
        if let uniqueId = contact.uniqueId {
            self.interactor?.addUser(with: uniqueId)
        } else {
            print("no unique id for user \(contact.displayName ?? "No name")")
        }
        print("+ selected rows: \(self.interactor?.selectedMembers ?? [])")
    }
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        print("deselected index path = \(indexPath)")
        let contact = contacts[indexPath.row]
        if let uniqueId = contact.uniqueId {
            self.interactor?.removeUser(with: uniqueId)
        } else {
            print("no unique id for user \(contact.displayName ?? "No name")")
        }
        print("- selected rows: \(self.interactor?.selectedMembers ?? [])")
    }
}

extension NewGroupViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?) {
        self.avatarView.image = image
    }
}
