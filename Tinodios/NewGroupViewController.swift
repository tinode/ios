//
//  NewGroupViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

protocol NewGroupDisplayLogic: class {
    func presentChat(with topicName: String)
}

class NewGroupViewController: UITableViewController {
    @IBOutlet weak var saveButtonItem: UIBarButtonItem!
    @IBOutlet weak var groupNameTextField: UITextField!
    @IBOutlet weak var privateTextField: UITextField!
    @IBOutlet weak var tagsTextField: TagsEditView!
    @IBOutlet weak var avatarView: RoundImageView!

    private var selectedContacts: [ContactHolder] = []

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

        self.tableView.register(UINib(nibName: "ContactViewCell", bundle: nil), forCellReuseIdentifier: "ContactViewCell")
        self.groupNameTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        self.privateTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        UiUtils.dismissKeyboardForTaps(onView: self.view)
        setup()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.tabBarController?.navigationItem.rightBarButtonItem = saveButtonItem
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.tabBarController?.navigationItem.rightBarButtonItem = nil
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        UiUtils.clearTextFieldError(textField)
    }

    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        print("Got segue \(segue.identifier ?? "unnamed")")
        if segue.identifier == "NewGroupToEditMembers" {
            let navigator = segue.destination as! UINavigationController
            let destination = navigator.viewControllers.first as! EditMembersViewController
            destination.delegate = self
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Section 0: use default.
        // Section 1: always show [+ Add members] then the list of members.
        return section == 0 ? super.tableView(tableView, numberOfRowsInSection: 0) : selectedContacts.count + 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section == 1 && indexPath.row > 0 else { return super.tableView(tableView, cellForRowAt: indexPath) }

        let cell = tableView.dequeueReusableCell(withIdentifier: "ContactViewCell", for: indexPath) as! ContactViewCell

        // Configure the cell...
        let contact = selectedContacts[indexPath.row - 1]

        cell.avatar.set(icon: contact.image, title: contact.displayName, id: contact.uniqueId)
        cell.title.text = contact.displayName
        cell.title.sizeToFit()
        cell.subtitle.text = contact.subtitle ?? contact.uniqueId
        cell.subtitle.sizeToFit()

        return cell
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // Hide empty header in the first section.
        return section == 0 ? CGFloat.leastNormalMagnitude : super.tableView(tableView, heightForHeaderInSection: section)
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
            let messageLabel = UILabel(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: tableView.bounds.height))
            messageLabel.text = "No members selected"
            messageLabel.textColor = .gray
            messageLabel.numberOfLines = 0
            messageLabel.textAlignment = .center
            messageLabel.font = .preferredFont(forTextStyle: .body)
            messageLabel.sizeToFit()

            tableView.backgroundView = messageLabel
        } else {
            tableView.backgroundView = nil
        }
    }
}

extension NewGroupViewController: NewGroupDisplayLogic {
    func presentChat(with topicName: String) {
        self.presentChatReplacingCurrentVC(with: topicName)
    }
}

extension NewGroupViewController: EditMembersDelegate {
    func editMembersInitialSelection(_: UIView) -> [String] {
        return selectedContacts.compactMap { $0.uniqueId }
    }

    func editMembersDidEndEditing(_: UIView, added: [String], removed: [String]) {
        self.interactor?.updateSelection(added: added, removed: removed)
    }

    func editMembersWillChangeState(_: UIView, uid: String, added: Bool, initiallySelected: Bool) -> Bool {
        return true
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
