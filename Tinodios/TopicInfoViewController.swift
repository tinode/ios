//
//  TopicInfoViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

class TopicInfoViewController: UITableViewController {

    // Number of rows in every section. '-1' means variable number of items
    private static let kSectionBasic = 0

    private static let kSectionMute = 1

    private static let kSectionActions = 2
    private static let kSectionActionsManageTags = 0
    private static let kSectionActionsDelMessages = 1
    private static let kSectionActionsLeaveGroup = 2
    private static let kSectionActionsLeaveConversation = 3
    private static let kSectionActionsDelTopic = 4
    private static let kSectionActionsBlock = 5
    private static let kSectionActionsReport = 6
    private static let kSectionActionsReportGroup = 7

    private static let kSectionPermissions = 3
    private static let kSectionPermissionsMine = 0
    private static let kSectionPermissionsPeer = 1

    private static let kSectionDefaultPermissions = 4
    private static let kSectionDefaultPermissionsAuth = 0
    private static let kSectionDefaultPermissionsAnon = 1

    private static let kSectionMembers = 5

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

    @IBOutlet weak var actionManageTags: UITableViewCell!
    @IBOutlet weak var actionDeleteMessages: UITableViewCell!
    @IBOutlet weak var actionDeleteGroup: UITableViewCell!
    @IBOutlet weak var actionLeaveGroup: UITableViewCell!
    @IBOutlet weak var actionLeaveConversation: UITableViewCell!
    @IBOutlet weak var actionBlockContact: UITableViewCell!
    @IBOutlet weak var actionReportContact: UITableViewCell!
    @IBOutlet weak var actionReportGroup: UITableViewCell!

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
        reloadData()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        reloadData()
    }

    private func setup() {
        self.tinode = Cache.tinode
        self.topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic
        guard self.topic != nil else {
            return
        }

        if self.topic.isGrpType {
            loadAvatarButton.isHidden = !topic.isManager
            showDefaultPermissions = topic.isManager
            showPeerPermissions = false
            showGroupMembers = topic.isManager || topic.isSharer
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
            forView: actionManageTags,
            action: #selector(TopicInfoViewController.manageTagsClicked),
            actionTarget: self)
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
            forView: actionBlockContact,
            action: #selector(TopicInfoViewController.blockContactClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionReportContact,
            action: #selector(TopicInfoViewController.reportContactClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionReportGroup,
            action: #selector(TopicInfoViewController.reportGroupClicked),
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
            presentationController: self, delegate: self, editable: true)
    }

    private func reloadData() {
        topicTitleTextView.text = topic.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name")
        topicTitleTextView.sizeToFit()
        topicIDLabel.text = topic?.name
        topicIDLabel.sizeToFit()
        let subtitle = topic.comment ?? ""
        topicSubtitleTextView.text = !subtitle.isEmpty ? subtitle : NSLocalizedString("Private info: not set", comment: "Placeholder text in editor")
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
            // FIXME: reload just the members section.
            tableView.reloadData()
        } else {
            peerNameLabel?.text = topic.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name")
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
        topic.updateMuted(muted: isChecked).then(
            onSuccess: UiUtils.ToastSuccessHandler,
            onFailure: { err in
                self.mutedSwitch.isOn = !isChecked
                if let e = err as? TinodeError, case .notConnected(_) = e {
                    UiUtils.showToast(message: NSLocalizedString("You are offline.", comment: "Toast notification"))
                }
                return nil
            }).thenFinally({
                DispatchQueue.main.async { self.reloadData() }
            })
    }

    @objc
    func topicTitleTapped(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("Edit Group", comment: "Alert title"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: nil))
        if topic.isOwner {
            alert.addTextField(configurationHandler: { textField in
                textField.placeholder = NSLocalizedString("Name of the group", comment: "Alert placeholder")
                textField.text = self.topic?.pub?.fn ?? ""
                textField.borderStyle = .none
                textField.font = UIFont.preferredFont(forTextStyle: .body)
            })
        }
        alert.addTextField(configurationHandler: { textField in
            textField.placeholder = NSLocalizedString("Additional info (private)", comment: "Alert placeholder")
            textField.text = self.topic?.comment ?? ""
            textField.borderStyle = .none
            textField.font = UIFont.preferredFont(forTextStyle: .body)
        })
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "Alert action"), style: .default,
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
                pub = VCard(fn: String(nt.prefix(UiUtils.kMaxTitleLength)), avatar: nil as Data?)
            }
        }
        var priv: PrivateType? = nil
        if let ns = newSubtitle {
            if topic.comment == nil || (topic.comment! != ns) {
                priv = PrivateType()
                priv!.comment = String(ns.prefix(UiUtils.kMaxTitleLength))
            }
        }
        if pub != nil || priv != nil {
            UiUtils.setTopicData(forTopic: topic, pub: pub, priv: priv)?.thenFinally {
                DispatchQueue.main.async { self.reloadData() }
            }
        }
    }

    private func changePermissions(acs: AcsHelper?, uid: String?, changeType: UiUtils.PermissionsChangeType, disabledPermissions: String?) {
        guard let acs = acs else {
            Cache.log.error("TopicInfoVC - can't change nil permissions")
            return
        }
        UiUtils.showPermissionsEditDialog(over: self, acs: acs, callback: {
            permissions in
            UiUtils.handlePermissionsChange(onTopic: self.topic, forUid: uid, changeType: changeType, newPermissions: permissions)?.then(onSuccess: self.promiseSuccessHandler)
        }, disabledPermissions: disabledPermissions)
    }

    @objc func permissionsTapped(sender: UITapGestureRecognizer) {
        switch sender.view { // apparently there is no need for === operator.
        case actionMyPermissions:
            if let acs = topic.accessMode {
                var disabled: String = ""
                if acs.isOwner {
                    // The owner should be able to change any permission except unsetting the 'O'
                    disabled = "O"
                } else {
                    // Allow accepting any of A S D O permissions but don't allow asking for them.
                    let controlled = AcsHelper(str: "ASDO")
                    if let notGiven = AcsHelper.diff(a1: controlled, a2: AcsHelper.and(a1: acs.given, a2: controlled)) {
                        disabled = notGiven.description
                    } else {
                        disabled = "ASDO"
                    }
                }
                changePermissions(acs: acs.want, uid: nil, changeType: .updateSelfSub, disabledPermissions: disabled)
            } else {
                Cache.log.error("Access mode is nil")
            }
        case actionPeerPermissions:
            changePermissions(acs: topic.getSubscription(for: self.topic.name)?.acs?.given, uid: topic.name, changeType: .updateSub, disabledPermissions: "ASDO")
        case actionAuthPermissions:
            changePermissions(acs: topic.defacs?.auth, uid: nil, changeType: .updateAuth, disabledPermissions: "O")
        case actionAnonPermissions:
            changePermissions(acs: topic.defacs?.anon, uid: nil, changeType: .updateAnon, disabledPermissions: "O")
        default:
            return
        }
    }

    private func deleteTopic() {
        topic.delete(hard: true).then(
            onSuccess: { msg in
                DispatchQueue.main.async {
                    self.performSegue(withIdentifier: "TopicInfo2Chats", sender: nil)
                }
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler)
    }

    private func blockContact() {
        topic.updateMode(uid: nil, update: "-JP").then(
            onSuccess: { msg in
                DispatchQueue.main.async {
                    self.performSegue(withIdentifier: "TopicInfo2Chats", sender: nil)
                }
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler)
    }

    private func reportTopic(reason: String) {
        blockContact();
        // Create and send spam report.
        let msg = Drafty().attachJSON([
            "action": JSONValue.string("report"),
            "target": JSONValue.string(self.topic.name)
            ])
        _ = Cache.tinode.publish(topic: Tinode.kTopicSys, head: Tinode.draftyHeaders(for: msg), content: msg)
    }

    @objc func deleteGroupClicked(sender: UITapGestureRecognizer) {
        guard topic.isOwner else {
            UiUtils.showToast(message: NSLocalizedString("Only Owner can delete group", comment: "Toast notification"))
            return
        }
        let alert = UIAlertController(title: NSLocalizedString("Delete the group?", comment: "Alert title"), message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Delete", comment: "Alert action"), style: .destructive,
            handler: { action in self.deleteTopic() }))
        present(alert, animated: true)
    }

    @objc func manageTagsClicked(sender: UITapGestureRecognizer) {
        UiUtils.presentManageTagsEditDialog(over: self, forTopic: self.topic)
    }

    @objc func deleteMessagesClicked(sender: UITapGestureRecognizer) {
        let handler: (Bool) -> Void = { (hard: Bool) -> Void in
            self.topic?.delMessages(hard: hard).thenCatch(UiUtils.ToastFailureHandler)
        }

        let alert = UIAlertController(title: NSLocalizedString("Clear all messages?", comment: "Alert title"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: nil))
        if topic.isDeleter {
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("For all", comment: "Alert action qualifier as in 'Delete for all'"), style: .destructive,
                handler: { action in handler(true) }))
        }
        alert.addAction(UIAlertAction(
            title: topic.isDeleter ? NSLocalizedString("For me", comment: "Alert action 'Delete for me'") : NSLocalizedString("OK", comment: "Alert action"), style: .destructive,
            handler: { action in handler(false) }))
        present(alert, animated: true)
    }

    @objc func leaveConversationClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("Leave the conversation?", comment: "Alert title"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Leave", comment: "Alert action"), style: .destructive,
            handler: { action in self.deleteTopic() }))
        present(alert, animated: true)
    }

    @objc func leaveGroupClicked(sender: UITapGestureRecognizer) {
        guard !topic.isOwner else {
            UiUtils.showToast(message: NSLocalizedString("Owner cannot leave the group", comment: "Toast notification"))
            return
        }

        let alert = UIAlertController(title: NSLocalizedString("Leave the group?", comment: "Alert title"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Leave", comment: "Alert action"), style: .destructive,
            handler: { action in self.deleteTopic() }))
        present(alert, animated: true)
    }

    @objc func blockContactClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("Block contact?", comment: "Alert action"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Block", comment: "Alert action"), style: .destructive,
            handler: { action in self.blockContact() }))
        present(alert, animated: true)
    }

    @objc func reportContactClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("Report contact?", comment: "Alert title"), message: NSLocalizedString("Also block and remove all messages", comment: "Alert explanation"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Report", comment: "Alert action"), style: .destructive,
            handler: { action in self.reportTopic(reason: "TODO") }))
        present(alert, animated: true)
    }

    @objc func reportGroupClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("Report Group?", comment: "Alert title"), message: NSLocalizedString("Also block and remove all messages", comment: "Alert explanation"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Report", comment: "Alert action"), style: .destructive,
            handler: { action in self.reportTopic(reason: "TODO") }))
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

        if indexPath.section == TopicInfoViewController.kSectionActions {
            if indexPath.row == TopicInfoViewController.kSectionActionsManageTags && (!(topic?.isGrpType ?? false) || !(topic?.isOwner ?? false)) {
                // P2P topic has no owner, hide [Manage Tags]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicInfoViewController.kSectionActionsDelMessages && (topic?.isChannel ?? false) {
                // Channel readers cannot delete messages
                return CGFloat.leastNonzeroMagnitude
            }
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
            if indexPath.row == TopicInfoViewController.kSectionActionsBlock && topic?.isGrpType ?? false {
                // Group topic, hide [Block Contact]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicInfoViewController.kSectionActionsReport && topic?.isGrpType ?? false {
                // Group topic, hide [Report Contact]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicInfoViewController.kSectionActionsReportGroup && (!(topic?.isGrpType ?? false) || (topic?.isOwner ?? false)) {
                // P2P topic or the owner, hide [Report Group]
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

    static func getAccessModeLabels(acs: Acs?, status: BaseDb.Status?) -> [AccessModeLabel]? {
        var result = [AccessModeLabel]()
        if let acs = acs {
            if acs.isModeDefined {
                if !acs.isNone {
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
                } else {
                    // The acs.mode is 'N' (none)
                    if !acs.isNoneGiven || acs.isNoneWant {
                        result.append(AccessModeLabel(color: AccessModeLabel.kColorGrayBorder, text: "invited"))
                    } else if acs.isNoneGiven && !acs.isNoneWant {
                        result.append(AccessModeLabel(color: AccessModeLabel.kColorGrayBorder, text: "requested"))
                    }
                }
            }
        }
        if let status = status, status == .queued {
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
        cell.title.text = isMe ? NSLocalizedString("You", comment: "This is 'you'") : (pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name"))
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
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert action"), style: .default, handler: { action in
            var ban: Bool
            switch memberAction {
            case .remove:
                ban = false
            case .ban:
                ban = true
            }
            self.topic.eject(user: uid, ban: ban).then(
                onSuccess: self.promiseSuccessHandler,
                onFailure: UiUtils.ToastFailureHandler)
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: nil))
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

        let alert = UIAlertController(title: sub.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name"), message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Send message", comment: "Alert action"), style: .default, handler: { action in
            if let topic = sub.user {
                self.presentChatReplacingCurrentVC(with: topic)
            } else {
                UiUtils.showToast(message: NSLocalizedString("Topic name missing", comment: "Toast notification"))
            }
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Change permissions", comment: "Alert action"), style: .default, handler: { action in
            guard let acsUnwrapped = sub.acs?.given, acsUnwrapped.isDefined else {
                UiUtils.showToast(message: NSLocalizedString("Can't change permissions for this user.", comment: "Toast notification"))
                return
            }
            self.changePermissions(acs: acsUnwrapped, uid: sub.user, changeType: .updateSub, disabledPermissions: nil)

        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Make owner", comment: "Alert action"), style: .default, handler: { action in
            guard let uid = sub.user else {
                UiUtils.showToast(message: NSLocalizedString("Can't make this user owner.", comment: "Toast notification"))
                return
            }
            self.topic.updateMode(uid: uid, update: "+O").then(
                onSuccess: self.promiseSuccessHandler,
                onFailure: UiUtils.ToastFailureHandler)
        }))
        let topicTitle = self.topic.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing topic name")
        let title = sub.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name")
        alert.addAction(UIAlertAction(title: NSLocalizedString("Remove", comment: "Alert action"), style: .default, handler: { action in
            self.showConfirmationDialog(
                forAction: .remove, withUid: sub.user,
                message: String(format: NSLocalizedString("Remove %@ from %@?", comment: "Confirmation"), title, topicTitle))
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Block", comment: "Alert action"), style: .default, handler: { action in
            self.showConfirmationDialog(
                forAction: .ban, withUid: sub.user,
                message: String(format: NSLocalizedString("Remove and ban %@ from %@?", comment: "Confirmation"), title, topicTitle))
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
}

extension TopicInfoViewController: EditMembersDelegate {
    func editMembersInitialSelection(_: UIView) -> [ContactHolder] {
        return subscriptions?.compactMap {
            return ContactHolder(displayName: $0.pub?.fn, image: $0.pub?.photo?.image(), uniqueId: $0.user)
        } ?? []
    }

    func editMembersDidEndEditing(_: UIView, added: [String], removed: [String]) {
         for uid in added {
            topic.invite(user: uid, in: nil).thenCatch(UiUtils.ToastFailureHandler)
         }
         for uid in removed {
            topic.eject(user: uid, ban: false).thenCatch(UiUtils.ToastFailureHandler)
         }
    }

    func editMembersWillChangeState(_: UIView, uid: String, added: Bool, initiallySelected: Bool) -> Bool {
        return !tinode.isMe(uid: uid) && (added || topic.isAdmin || !initiallySelected)
    }
}

extension TopicInfoViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?, mimeType: String?, fileName: String?) {
        guard let image = image?.resize(width: UiUtils.kAvatarSize, height: UiUtils.kAvatarSize, clip: true) else {
            return
        }
        UiUtils.updateAvatar(forTopic: self.topic, image: image)?.then(onSuccess: self.promiseSuccessHandler)
    }
}
