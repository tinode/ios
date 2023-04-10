//
//  NewGroupViewController.swift
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK

protocol NewGroupDisplayLogic: AnyObject {
    func presentChat(with topicName: String)
}

class NewGroupViewController: UITableViewController {
    @IBOutlet weak var saveButtonItem: UIBarButtonItem!
    @IBOutlet weak var groupNameTextField: UITextField!
    @IBOutlet weak var privateTextField: UITextField!
    @IBOutlet weak var tagsTextField: TagsEditView!
    @IBOutlet weak var avatarView: RoundImageView!
    @IBOutlet weak var channelSwitch: UISwitch!

    private var selectedContacts: [ContactHolder] = []
    private var selectedUids = Set<String>()
    var selectedMembers: [String] { return selectedUids.map { $0 } }

    private var avatarReceived: Bool = false

    private var imagePicker: ImagePicker!

    private func setup() {
        self.imagePicker = ImagePicker(presentationController: self, delegate: self, editable: true)
        self.tagsTextField.onVerifyTag = { (_, tag) in
            return Utils.isValidTag(tag: tag)
        }
        if !Cache.isContactSynchronizerActive() {
            Cache.synchronizeContactsPeriodically()
        }

        // Add me to selectedUids and selectedContacts.
        if let myUid = Cache.tinode.myUid {
            selectedContacts = ContactsManager.default.fetchContacts(withUids: [myUid]) ?? []
            if !selectedContacts.isEmpty {
                selectedUids.insert(myUid)
            }
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
        textField.clearErrorSign()
    }

    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Section 0: use default.
        // Section 1: always show [+ Add members] then the list of members.
        return section == 0 ? super.tableView(tableView, numberOfRowsInSection: 0) : selectedContacts.count + 1
    }

    // Group members.
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section == 1 && indexPath.row > 0 else { return super.tableView(tableView, cellForRowAt: indexPath) }

        let cell = tableView.dequeueReusableCell(withIdentifier: "ContactViewCell", for: indexPath) as! ContactViewCell

        // Configure the cell...
        let contact = selectedContacts[indexPath.row - 1]

        cell.avatar.set(pub: contact.pub, id: contact.uniqueId, deleted: false)
        cell.title.text = contact.pub?.fn
        cell.title.sizeToFit()
        cell.subtitle.text = contact.subtitle ?? contact.uniqueId
        cell.subtitle.sizeToFit()

        return cell
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // Hide empty header in the first section.
        return section == 0 ? CGFloat.leastNormalMagnitude : super.tableView(tableView, heightForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // Otherwise crash
        return indexPath.section == 0 || indexPath.row == 0 ? super.tableView(tableView, heightForRowAt: indexPath) : 60
    }
    override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        // Otherwise crash
        return indexPath.section == 0 || indexPath.row == 0 ? super.tableView(tableView, indentationLevelForRowAt: indexPath) : 0
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "NewGroupToEditMembers" {
            let navigator = segue.destination as! UINavigationController
            let destination = navigator.viewControllers.first as! EditMembersViewController
            destination.delegate = self
        }
    }

    // MARK: - UI event handlers.
    @IBAction func loadAvatarClicked(_ sender: Any) {
        // Get avatar image
        self.imagePicker.present(from: self.view)
    }

    @IBAction func saveButtonClicked(_ sender: Any) {
        let groupName = UiUtils.ensureDataInTextField(groupNameTextField, maxLength: UiUtils.kMaxTitleLength)
        let tinode = Cache.tinode
        let members = selectedMembers.filter { !tinode.isMe(uid: $0) }
        if members.isEmpty {
            UiUtils.showToast(message: NSLocalizedString("Select at least one group member", comment: "Error message"))
            return
        }
        // Optional
        let privateInfo = String((privateTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(UiUtils.kMaxTitleLength))
        guard !groupName.isEmpty else { return }
        let avatar = avatarReceived ? avatarView.image?.resize(width: CGFloat(UiUtils.kMaxAvatarSize), height: CGFloat(UiUtils.kMaxAvatarSize), clip: true) : nil
        createGroupTopic(titled: groupName, subtitled: privateInfo, with: tagsTextField.tags, consistingOf: members, withAvatar: avatar, asChannel: channelSwitch.isOn)
    }

    /// Show message that no members are selected.
    private func toggleNoSelectedMembersNote(on show: Bool) {
        if show {
            let messageLabel = UILabel(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: tableView.bounds.height))
            messageLabel.text = NSLocalizedString("No members selected", comment: "Placeholder when no members are selected")
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

    private func createGroupTopic(titled name: String, subtitled subtitle: String, with tags: [String]?, consistingOf members: [String], withAvatar avatar: UIImage?, asChannel isChannel: Bool) {
        let topic = DefaultComTopic(in: Cache.tinode, forwardingEventsTo: nil, isChannel: isChannel)
        func doCreate(pub: TheCard) {
            topic.pub = pub
            topic.priv = ["comment": .string(subtitle)] // No need to use Tinode.kNullValue here
            topic.tags = tags
            topic.subscribe().then(
                onSuccess: { _ in
                    for u in members {
                        topic.invite(user: u, in: nil)
                    }
                    // Need to unsubscribe because routing to MessageVC (below)
                    // will subscribe to the topic again.
                    topic.leave()
                    // Route to chat.
                    self.presentChat(with: topic.name)
                    return nil
                },
                onFailure: UiUtils.ToastFailureHandler)
        }

        guard let avatar = avatar?.resize(width: UiUtils.kMaxAvatarSize, height: UiUtils.kMaxAvatarSize, clip: true), avatar.size.width >= UiUtils.kMinAvatarSize && avatar.size.height >= UiUtils.kMinAvatarSize else {
            doCreate(pub: TheCard(fn: name))
            return
        }

        if let imageBits = avatar.pixelData(forMimeType: Photo.kDefaultType) {
            if imageBits.count > UiUtils.kMaxInbandAvatarBytes {
                // Sending image out of band.
                Cache.getLargeFileHelper().startAvatarUpload(mimetype: Photo.kDefaultType, data: imageBits, topicId: topic.name, completionCallback: {(srvmsg, error) in
                    guard let error = error else {
                        let thumbnail = avatar.resize(width: UiUtils.kAvatarPreviewDimensions, height: UiUtils.kAvatarPreviewDimensions, clip: true)
                        let photo = Photo(data: thumbnail?.pixelData(forMimeType: Photo.kDefaultType), ref: srvmsg?.ctrl?.getStringParam(for: "url"), width: Int(avatar.size.width), height: Int(avatar.size.height))
                        doCreate(pub: TheCard(fn: name, avatar: photo))
                        return
                    }
                    UiUtils.ToastFailureHandler(err: error)
                })
            } else {
                doCreate(pub: TheCard(fn: name, avatar: avatar))
            }
        } else {
            UiUtils.ToastFailureHandler(err: ImageProcessingError.invalidImage)
        }
    }
}

extension NewGroupViewController: NewGroupDisplayLogic {
    func presentChat(with topicName: String) {
        self.presentChatReplacingCurrentVC(with: topicName)
    }
}

extension NewGroupViewController: EditMembersDelegate {
    func editMembersInitialSelection(_: UIView) -> [ContactHolder] {
        return selectedContacts
    }

    func editMembersDidEndEditing(_: UIView, added: [String], removed: [String]) {
        selectedUids.formUnion(added)
        selectedUids.subtract(removed)
        var success = true
        // A simple tableView.reloadData() results in a crash. Thus doing this crazy stuff.
        let removedPaths = removed.map({(rem: String) -> IndexPath in
            if let row = selectedContacts.firstIndex(where: { h in h.uniqueId == rem }) {
                return IndexPath(row: row + 1, section: 1)
            } else {
                success = false
                UiUtils.showToast(message: "Removed non-existent user.")
                return IndexPath(row: -1, section: 1)
            }
        })
        guard success else { return }
        let newSelection = ContactsManager.default.fetchContacts(withUids: selectedMembers) ?? []
        let addedPaths = added.map({(add: String) -> IndexPath in
            if let row = newSelection.firstIndex(where: { h in h.uniqueId == add }) {
                return IndexPath(row: row + 1, section: 1)
            } else {
                UiUtils.showToast(message: "Added non-existent user")
                return IndexPath(row: -1, section: 1)
            }
        })
        guard success && selectedUids.count == newSelection.count else {
            UiUtils.showToast(message: "Invalid member selection. Try again.")
            return
        }

        tableView.beginUpdates()
        selectedContacts = newSelection
        self.tableView.deleteRows(at: removedPaths, with: .automatic)
        self.tableView.insertRows(at: addedPaths, with: .automatic)
        tableView.endUpdates()
    }

    func editMembersWillChangeState(_: UIView, uid: String, added: Bool, initiallySelected: Bool) -> Bool {
        return !Cache.tinode.isMe(uid: uid)
    }
}

extension NewGroupViewController: ImagePickerDelegate {
    func didSelect(media: ImagePickerMediaType?) {
        guard case .image(let image, _, _) = media,
            let image = image?.resize(width: CGFloat(UiUtils.kMaxAvatarSize), height: CGFloat(UiUtils.kMaxAvatarSize), clip: true) else { return }

        self.avatarView.image = image
        avatarReceived = true
    }
}
