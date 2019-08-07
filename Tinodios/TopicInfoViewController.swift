//
//  TopicInfoViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

class TopicInfoViewController: UITableViewController {

    // Number of rows in every section. '-1' means variable number of items
    private static let kSectionBasic = 0

    private static let kSectionMute = 1

    private static let kSectionActions = 2
    private static let kSectionActionsDelMessages = 0
    private static let kSectionActionsLeaveGroup = 1
    private static let kSectionActionsLeaveConversation = 2
    private static let kSectionActionsDelTopic = 3

    private static let kSectionPermissions = 3
    private static let kSectionPermissionsMine = 0
    private static let kSectionPermissionsPeer = 1

    private static let kSectionDefaultPermissions = 4
    private static let kSectionDefaultPermissionsAuth = 0
    private static let kSectionDefaultPermissionsAnon = 1

    private static let kSectionMembers = 5
    private static let kSectionMembersButtons = 0

    @IBOutlet weak var topicTitleTextView: UITextView!
    @IBOutlet weak var topicSubtitleTextView: UITextView!
    @IBOutlet weak var avatarImage: RoundImageView!
    @IBOutlet weak var loadAvatarButton: UIButton!
    @IBOutlet weak var mutedSwitch: UISwitch!
    @IBOutlet weak var topicIDLabel: UILabel!

    @IBOutlet weak var actionMyPermissions: UITableViewCell!
    @IBOutlet weak var myPermissionsLabel: UILabel!
    @IBOutlet weak var actionPeerPermissions: UITableViewCell!
    @IBOutlet weak var peerNameLabel: UILabel!
    @IBOutlet weak var peerPermissionsLabel: UILabel!

    @IBOutlet weak var authUsersPermissionsLabel: UILabel!
    @IBOutlet weak var anonUsersPermissionsLabel: UILabel!
    @IBOutlet weak var actionAuthPermissions: UITableViewCell!
    @IBOutlet weak var actionAnonPermissions: UITableViewCell!

    @IBOutlet weak var actionDeleteMessages: UITableViewCell!
    @IBOutlet weak var actionDeleteGroup: UITableViewCell!
    @IBOutlet weak var actionLeaveGroup: UITableViewCell!
    @IBOutlet weak var actionLeaveConversation: UITableViewCell!

    var topicName = ""
    private var topic: DefaultComTopic!
    private var tinode: Tinode!
    private var imagePicker: ImagePicker!

    private var subscriptions: [Subscription<VCard, PrivateType>]?

    // Show row with Peer's permissions (p2p topic)
    private var showPeerPermissions: Bool = false
    // Show section with default topic permissions (manager of a grp topic)
    private var showDefaultPermissions: Bool = false
    // Show section with group members
    private var showGroupMembers: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        reloadData()
    }

    private func setup() {
        self.tinode = Cache.getTinode()
        self.topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic
        guard self.topic != nil else {
            return
        }

        if self.topic.isGrpType {
            loadAvatarButton.isHidden = !topic.isManager
            showDefaultPermissions = topic.isManager
            showPeerPermissions = false
            showGroupMembers = true
            tableView.register(UINib(nibName: "ContactViewCell", bundle: nil), forCellReuseIdentifier: "ContactViewCell")
        } else {
            loadAvatarButton.isHidden = true
            showDefaultPermissions = false
            showGroupMembers = false
            showPeerPermissions = true
        }
        UiUtils.setupTapRecognizer(
            forView: topicSubtitleTextView,
            action: #selector(TopicInfoViewController.topicTitleTapped),
            actionTarget: self)
        if topic.isOwner {
            UiUtils.setupTapRecognizer(
                forView: topicTitleTextView,
                action: #selector(TopicInfoViewController.topicTitleTapped),
                actionTarget: self)
        }

        UiUtils.setupTapRecognizer(
            forView: actionDeleteMessages,
            action: #selector(TopicInfoViewController.deleteMessagesClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionDeleteGroup,
            action: #selector(TopicInfoViewController.deleteGroupClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionLeaveGroup,
            action: #selector(TopicInfoViewController.leaveGroupClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionLeaveConversation,
            action: #selector(TopicInfoViewController.leaveConversationClicked),
            actionTarget: self)

        UiUtils.setupTapRecognizer(
            forView: actionMyPermissions,
            action: #selector(TopicInfoViewController.permissionsTapped),
            actionTarget: self)

        if showPeerPermissions {
            UiUtils.setupTapRecognizer(
                forView: actionPeerPermissions,
                action: #selector(TopicInfoViewController.permissionsTapped),
                actionTarget: self)
        }

        if showDefaultPermissions {
            UiUtils.setupTapRecognizer(
                forView: actionAuthPermissions,
                action: #selector(TopicInfoViewController.permissionsTapped),
                actionTarget: self)
            UiUtils.setupTapRecognizer(
                forView: actionAnonPermissions,
                action: #selector(TopicInfoViewController.permissionsTapped),
                actionTarget: self)
        }

        self.imagePicker = ImagePicker(
            presentationController: self, delegate: self)
    }

    private func reloadData() {
        topicTitleTextView.text = topic.pub?.fn ?? "Unknown"
        topicTitleTextView.sizeToFit()
        topicIDLabel.text = topic?.name
        topicIDLabel.sizeToFit()
        let subtitle = topic.comment ?? ""
        topicSubtitleTextView.text = !subtitle.isEmpty ? subtitle : "Private info: not set"
        topicSubtitleTextView.sizeToFit()
        avatarImage.set(icon: topic.pub?.photo?.image(), title: topic.pub?.fn, id: topic?.name)
        avatarImage.letterTileFont = self.avatarImage.letterTileFont.withSize(CGFloat(50))
        mutedSwitch.isOn = topic.isMuted
        let acs = topic.accessMode

        if self.topic.isGrpType {
            authUsersPermissionsLabel?.text = topic.defacs?.getAuth()
            anonUsersPermissionsLabel?.text = topic.defacs?.getAnon()
            myPermissionsLabel?.text = acs?.modeString
            subscriptions = topic.getSubscriptions()
            tableView.reloadData()
        } else {
            peerNameLabel?.text = topic.pub?.fn ?? "Unknown"
            myPermissionsLabel?.text = acs?.wantString
            let sub = topic.getSubscription(for: self.topic.name)
            peerPermissionsLabel?.text = sub?.acs?.givenString
        }
    }

    @IBAction func loadAvatarClicked(_ sender: Any) {
        imagePicker.present(from: self.view)
    }

    @IBAction func mutedSwitched(_ sender: Any) {
        let isChecked = mutedSwitch.isOn
        do {
            try topic.updateMuted(muted: isChecked)?.then(
                onSuccess: UiUtils.ToastSuccessHandler,
                onFailure: { err in
                    self.mutedSwitch.isOn = !isChecked
                    return nil
                })?.thenFinally(finally: {
                    DispatchQueue.main.async { self.reloadData() }
                })
        } catch TinodeError.notConnected(_) {
            mutedSwitch.isOn = !isChecked
            UiUtils.showToast(message: "You are offline.")
        } catch {
            mutedSwitch.isOn = !isChecked
        }
    }

    @objc
    func topicTitleTapped(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: "Edit Topic", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        if topic.isOwner {
            alert.addTextField(configurationHandler: { textField in
                textField.placeholder = "Name of the group"
                textField.text = self.topic?.pub?.fn ?? ""
            })
        }
        alert.addTextField(configurationHandler: { textField in
            textField.placeholder = "Additional info (private)"
            textField.text = self.topic?.comment ?? ""
        })
        alert.addAction(UIAlertAction(
            title: "OK", style: .default,
            handler: { action in
                let textFields = alert.textFields!
                let newTitle = self.topic.isOwner ? textFields[0].text : nil
                let newSubtitle = textFields[self.topic.isOwner ? 1 : 0].text
                self.updateTitles(newTitle: newTitle, newSubtitle: newSubtitle)
        }))
        self.present(alert, animated: true)
    }

    private func updateTitles(newTitle: String?, newSubtitle: String?) {
        var pub: VCard? = nil
        if let nt = newTitle {
            if let oldPub = topic.pub, oldPub.fn != nt {
                pub = VCard(fn: nt, avatar: nil as Data?)
            }
        }
        var priv: PrivateType? = nil
        if let ns = newSubtitle {
            if let oldComment = topic.comment, oldComment != ns {
                priv = PrivateType()
                priv!.comment = ns
            }
        }
        if pub != nil || priv != nil {
            UiUtils.setTopicData(forTopic: topic, pub: pub, priv: priv)
        }
    }

    private func getAcsAndPermissionsChangeType(for sender: UIView) -> (AcsHelper?, String?, UiUtils.PermissionsChangeType?, String?) {
        if sender === actionMyPermissions {
            return (topic.accessMode?.want, nil, .updateSelfSub, "ASDO")
        }
        if sender === actionPeerPermissions {
            return (self.topic.getSubscription(for: self.topic.name)?.acs?.given, topic.name, .updateSub, "ASDO")
        }
        if sender === actionAuthPermissions {
            return (topic.defacs?.auth, nil, .updateAuth, "O")
        }
        if sender === actionAnonPermissions {
            return (topic.defacs?.anon, nil, .updateAnon, "O")
        }
        return (nil, nil, nil, nil)
    }

    private func changePermissions(acs: AcsHelper, uid: String?, changeType: UiUtils.PermissionsChangeType, disabledPermissions: String?) {
        UiUtils.showPermissionsEditDialog(over: self, acs: acs, callback: {
            permissions in
            _ = try? UiUtils.handlePermissionsChange(onTopic: self.topic, forUid: uid, changeType: changeType, newPermissions: permissions)?.then(onSuccess: self.promiseSuccessHandler)
        }, disabledPermissions: disabledPermissions)
    }

    @objc func permissionsTapped(sender: UITapGestureRecognizer) {
        guard let v = sender.view else {
            print("Tap from no sender view... quitting")
            return
        }
        let (acs, uid, changeTypeOptional, disablePermissions) = getAcsAndPermissionsChangeType(for: v)
        guard let acsUnwrapped = acs, let changeType = changeTypeOptional else {
            print("could not get acs")
            return
        }
        self.changePermissions(acs: acsUnwrapped, uid: uid, changeType: changeType, disabledPermissions: disablePermissions)
    }

    private func deleteTopic() {
        do {
            try topic.delete()?.then(
                onSuccess: { msg in
                    DispatchQueue.main.async {
                        let storyboard = UIStoryboard(name: "Main", bundle: nil)
                        let destinationVC = storyboard.instantiateViewController(withIdentifier: "ChatsNavigator") as! UINavigationController

                        self.show(destinationVC, sender: nil)
                    }
                    return nil
                },
                onFailure: UiUtils.ToastFailureHandler)
        } catch TinodeError.notConnected(let e) {
            UiUtils.showToast(message: "You are offline \(e)")
        } catch {
            UiUtils.showToast(message: "Action failed \(error)")
        }
    }

    @objc func deleteGroupClicked(sender: UITapGestureRecognizer) {
        guard topic.isOwner else {
            UiUtils.showToast(message: "Only Owner can delete group")
            return
        }
        let alert = UIAlertController(title: "Delete the group?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: "Delete", style: .destructive,
            handler: { action in self.deleteTopic() }))
        present(alert, animated: true)
    }

    @objc func deleteMessagesClicked(sender: UITapGestureRecognizer) {
        let handler: (Bool) -> Void = { (hard: Bool) -> Void in
            do {
                try self.topic?.delMessages(hard: hard)?.thenCatch(onFailure: UiUtils.ToastFailureHandler)
            } catch {
                UiUtils.showToast(message: "Failed to delete messages: \(error)")
            }
        }

        let alert = UIAlertController(title: "Clear all messages?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        if topic.isDeleter {
            alert.addAction(UIAlertAction(
                title: "For all", style: .destructive,
                handler: { action in handler(true) }))
        }
        alert.addAction(UIAlertAction(
            title: topic.isDeleter ? "For me" : "OK", style: .destructive,
            handler: { action in handler(false) }))
        present(alert, animated: true)
    }

    @objc func leaveConversationClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: "Leave the conversation?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: "Leave", style: .destructive,
            handler: { action in self.deleteTopic() }))
        present(alert, animated: true)
    }

    @objc func leaveGroupClicked(sender: UITapGestureRecognizer) {
        guard !topic.isOwner else {
            UiUtils.showToast(message: "Owner cannot leave the group")
            return
        }

        let alert = UIAlertController(title: "Leave the group?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: "Leave", style: .destructive,
            handler: { action in self.deleteTopic() }))
        present(alert, animated: true)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "TopicInfo2EditMembers" {
            let navigator = segue.destination as! UINavigationController
            let destination = navigator.viewControllers.first as! EditMembersViewController
            destination.delegate = self
        }
    }

    private func promiseSuccessHandler(msg: ServerMessage?) throws -> PromisedReply<ServerMessage>? {
        DispatchQueue.main.async { self.reloadData() }
        return nil
    }
}

extension TopicInfoViewController : UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return UIModalPresentationStyle.none
    }
}

extension TopicInfoViewController {
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == TopicInfoViewController.kSectionMembers {
            return showGroupMembers ? (subscriptions?.count ?? 0) + 1 : 0
        }
        if section == TopicInfoViewController.kSectionDefaultPermissions && !showDefaultPermissions {
            return 0
        }
        if section == TopicInfoViewController.kSectionPermissions && !showPeerPermissions {
            return 1
        }
        return super.tableView(tableView, numberOfRowsInSection: section)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == TopicInfoViewController.kSectionMembers && indexPath.row != 0 {
            return 60
        }

        if indexPath.section == TopicInfoViewController.kSectionActions && indexPath.row > 0 {
            if indexPath.row == TopicInfoViewController.kSectionActionsLeaveGroup && !(topic?.isGrpType ?? false) {
                // P2P topic, hide [Leave Group]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicInfoViewController.kSectionActionsLeaveConversation && topic?.isGrpType ?? false {
                // Group topic, hide [Leave Conversation]
                return CGFloat.leastNonzeroMagnitude
            }
            // Hide either [Leave] or [Delete Topic] actions.
            if indexPath.row == TopicInfoViewController.kSectionActionsLeaveGroup && topic?.isOwner ?? false {
                // Owner, hide [Leave]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicInfoViewController.kSectionActionsDelTopic && !(topic?.isOwner ?? false) {
                // Not an owner, hide [Delete Topic]
                return CGFloat.leastNonzeroMagnitude
            }
        }

        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == TopicInfoViewController.kSectionMembers && !showGroupMembers {
            return nil
        }
        if section == TopicInfoViewController.kSectionDefaultPermissions && !showDefaultPermissions {
            return nil
        }

        return super.tableView(tableView, titleForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {

        // Hide empty header in the first section.
        if section == TopicInfoViewController.kSectionBasic {
            return CGFloat.leastNormalMagnitude
        }

        if section == TopicInfoViewController.kSectionMembers && !showGroupMembers {
            return CGFloat.leastNormalMagnitude
        }

        if section == TopicInfoViewController.kSectionDefaultPermissions && !showDefaultPermissions {
            return CGFloat.leastNormalMagnitude
        }

        return super.tableView(tableView, heightForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        return 0
    }

    struct AccessModeLabel {
        public static let kColorGrayBorder = UIColor(fromHexCode: 0xff9e9e9e)
        public static let kColorGreenBorder = UIColor(fromHexCode: 0xff4caf50)
        public static let kColorRedBorder = UIColor(fromHexCode: 0xffe57373)
        public static let kColorYellowBorder = UIColor(fromHexCode: 0xffffca28)
        let color: UIColor
        let text: String
    }

    static func getAccessModeLabels(acs: Acs?, status: Int?) -> [AccessModeLabel]? {
        var result = [AccessModeLabel]()
        if let acs = acs {
            if acs.isModeDefined {
                if !acs.isJoiner || (!acs.isWriter && !acs.isReader) {
                    result.append(AccessModeLabel(color: AccessModeLabel.kColorRedBorder, text: "blocked"))
                } else if acs.isOwner {
                    result.append(AccessModeLabel(color: AccessModeLabel.kColorGreenBorder, text: "owner"))
                } else if acs.isAdmin {
                    result.append(AccessModeLabel(color: AccessModeLabel.kColorGreenBorder, text: "admin"))
                } else if !acs.isWriter {
                    result.append(AccessModeLabel(color: AccessModeLabel.kColorYellowBorder, text: "read-only"))
                } else if !acs.isReader {
                    result.append(AccessModeLabel(color: AccessModeLabel.kColorYellowBorder, text: "write-only"))
                }
            } else if !acs.isInvalid {
                // The mode is undefined (NONE)
                if acs.isGivenDefined || !acs.isWantDefined {
                    result.append(AccessModeLabel(color: AccessModeLabel.kColorGrayBorder, text: "invited"))
                } else if !acs.isGivenDefined && acs.isWantDefined {
                    result.append(AccessModeLabel(color: AccessModeLabel.kColorGrayBorder, text: "requested"))
                } else {
                    // Undefined state.
                    result.append(AccessModeLabel(color: AccessModeLabel.kColorGrayBorder, text: "undefined"))
                }
            }
        }
        if let status = status, status == BaseDb.kStatusQueued {
            result.append(AccessModeLabel(color: AccessModeLabel.kColorGrayBorder, text: "pending"))
        }
        return !result.isEmpty ? result : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section != TopicInfoViewController.kSectionMembers {
            return super.tableView(tableView, cellForRowAt: indexPath)
        }

        if indexPath.row == 0 {
            // Row with [Add members] and [Leave] buttons.
            return super.tableView(tableView, cellForRowAt: indexPath)
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "ContactViewCell", for: indexPath) as! ContactViewCell

        // Configure the cell...
        let sub = subscriptions![indexPath.row - 1]
        let uid = sub.user
        let isMe = self.tinode.isMe(uid: uid)
        let pub = sub.pub

        cell.avatar.set(icon: pub?.photo?.image(), title: pub?.fn, id: uid)
        cell.title.text = isMe ? "You" : (pub?.fn ?? "Unknown")
        cell.title.sizeToFit()
        cell.subtitle.text = sub.acs?.givenString
        for l in cell.statusLabels {
            l.isHidden = true
        }
        if let accessLabels = TopicInfoViewController.getAccessModeLabels(acs: sub.acs, status: (sub.payload as? StoredSubscription)?.status) {
            for i in 0..<accessLabels.count {
                cell.statusLabels[i].isHidden = false
                cell.statusLabels[i].text = accessLabels[i].text
                cell.statusLabels[i].sizeToFit()
                cell.statusLabels[i].textInsets = UIEdgeInsets(top: CGFloat(7), left: CGFloat(7), bottom: CGFloat(5), right: CGFloat(5))
                cell.statusLabels[i].textColor = accessLabels[i].color
                cell.statusLabels[i].layer.borderWidth = 1
                cell.statusLabels[i].layer.borderColor = accessLabels[i].color.cgColor
            }
        }
        cell.accessoryType = isMe ? .none : .disclosureIndicator

        return cell
    }

    enum MemberActinos {
        case remove, ban
    }
    private func showConfirmationDialog(forAction memberAction: MemberActinos, withUid uid: String?,
                                        message: String) {
        guard let uid = uid else { return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { action in
            var ban: Bool
            switch memberAction {
            case .remove:
                ban = false
            case .ban:
                ban = true
            }
            _ = try? self.topic.eject(user: uid, ban: ban)?.then(
                onSuccess: self.promiseSuccessHandler,
                onFailure: UiUtils.ToastFailureHandler)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated:  true)

        guard indexPath.section == TopicInfoViewController.kSectionMembers && indexPath.row != 0 else {
            return
        }

        let sub = subscriptions![indexPath.row - 1]
        if self.tinode.isMe(uid: sub.user) {
            return
        }

        let alert = UIAlertController(title: sub.pub?.fn ?? "Unknown", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Send message", style: .default, handler: { action in
            if let topic = sub.user {
                self.presentChatReplacingCurrentVC(with: topic)
            } else {
                UiUtils.showToast(message: "Topic name missing")
            }
        }))
        alert.addAction(UIAlertAction(title: "Change permissions", style: .default, handler: { action in
            guard let acsUnwrapped = sub.acs?.given, acsUnwrapped.isDefined else {
                UiUtils.showToast(message: "Can't change permissions for this user.")
                return
            }
            self.changePermissions(acs: acsUnwrapped, uid: sub.user, changeType: .updateSub, disabledPermissions: nil)

        }))
        alert.addAction(UIAlertAction(title: "Make owner", style: .default, handler: { action in
            guard let uid = sub.user else {
                UiUtils.showToast(message: "Can't make this user owner.")
                return
            }
            do {
                try self.topic.updateMode(uid: uid, update: "+O")?.then(
                    onSuccess: self.promiseSuccessHandler,
                    onFailure: UiUtils.ToastFailureHandler)
            } catch {
                UiUtils.showToast(message: "Operation failed \(error).")
            }
        }))
        let topicTitle = self.topic.pub?.fn ?? "Unknown"
        let title = sub.pub?.fn ?? "Unknown"
        alert.addAction(UIAlertAction(title: "Remove", style: .default, handler: { action in
            self.showConfirmationDialog(
                forAction: .remove, withUid: sub.user,
                message: "Remove \(title) from \(topicTitle)?")
        }))
        alert.addAction(UIAlertAction(title: "Block", style: .default, handler: { action in
            self.showConfirmationDialog(
                forAction: .ban, withUid: sub.user,
                message: "Remove and ban \(title) from \(topicTitle)?")
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
}

extension TopicInfoViewController: EditMembersDelegate {
    func editMembersInitialSelection(_: UIView) -> [String] {
        return subscriptions?.compactMap { print("Selected contact: \($0.user ?? "nil")"); return $0.user } ?? []
    }

    func editMembersDidEndEditing(_: UIView, added: [String], removed: [String]) {
         print("inviting \(added)")
         for uid in added {
            _ = try? topic.invite(user: uid, in: nil)?.thenCatch(onFailure: UiUtils.ToastFailureHandler)
         }
         print("ejecting \(removed)")
         for uid in removed {
            _ = try? topic.eject(user: uid, ban: false)?.thenCatch(onFailure: UiUtils.ToastFailureHandler)
         }
    }

    func editMembersWillChangeState(_: UIView, uid: String, added: Bool, initiallySelected: Bool) -> Bool {
        return added || topic.isAdmin || !initiallySelected
    }
}

extension TopicInfoViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?, mimeType: String?, fileName: String?) {
        guard let image = image?.resize(width: UiUtils.kAvatarSize, height: UiUtils.kAvatarSize, clip: true) else {
            print("No image specified or failed to resize - skipping")
            return
        }
        _ = try? UiUtils.updateAvatar(forTopic: self.topic, image: image)?.then(
            onSuccess: self.promiseSuccessHandler)
    }
}
