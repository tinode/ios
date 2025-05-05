//
//  TopicInfoViewController.swift
//
//  Copyright © 2019-2025 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

class TopicInfoViewController: UITableViewController {

    private static let kSectionBasic = 0
    private static let kSectionBasicAvatar = 0
    private static let kSectionBasicTitle = 1
    private static let kSectionBasicLastSeen = 2

    private static let kSectionExtended = 1
    private static let kSectionExtendedAddress = 0
    private static let kSectionExtendedAlias = 1
    private static let kSectionExtendedVerified = 2
    private static let kSectionExtendedStaff = 3
    private static let kSectionExtendedDanger = 4
    private static let kSectionExtendedPrivate = 5
    private static let kSectionExtendedDescription = 6

    private static let kSectionQuickAction = 2
    private static let kSectionQuickActionMute = 0
    private static let kSectionQuickActionArchive = 1

    private static let kSectionActions = 3
    private static let kSectionActionsAdminSecurity = 0

    private static let kSectionMembers = 4

    @IBOutlet weak var topicTitleLabel: UILabel!
    @IBOutlet weak var topicIDLabel: UILabel!
    @IBOutlet weak var lastSeenTimestampLabel: UILabel!
    @IBOutlet weak var aliasLabel: UILabel!
    @IBOutlet weak var topicPrivateTextView: UITextView!
    @IBOutlet weak var topicDescriptionTextView: UITextView!

    @IBOutlet weak var avatarImage: RoundImageView!

    @IBOutlet weak var mutedSwitch: UISwitch!
    @IBOutlet weak var archivedSwitch: UISwitch!

    var topicName = ""
    private var topic: DefaultComTopic!
    private var tinode: Tinode!
    private var imagePicker: ImagePicker!

    private var subscriptions: [Subscription<TheCard, PrivateType>]?

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
            showGroupMembers = topic.isManager || topic.isSharer
            tableView.register(UINib(nibName: "ContactViewCell", bundle: nil), forCellReuseIdentifier: "ContactViewCell")
        } else {
            showGroupMembers = false
        }
    }

    private func reloadData() {
        let isSlf = topic.isSlfType

        // Disable and hide EDIT buttin for SLF topic.
        if isSlf, let editButton = self.navigationItem.rightBarButtonItem {
            editButton.isEnabled = false
            editButton.tintColor = UIColor.clear
        }

        topicTitleLabel.text = isSlf ? NSLocalizedString("Saved messages", comment: "Title for slf topic") : topic.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name")
        topicTitleLabel.textAlignment = .center

        let descPlaceholder: String? = topic.isOwner ? NSLocalizedString("Оptional description", comment: "Placeholder for missing topic description") : nil
        let isEmpty = (topic.pub?.note?.isEmpty ?? true) && !isSlf
        topicDescriptionTextView.textColor = isEmpty ? .placeholderText : .secondaryLabel
        topicDescriptionTextView.text = isEmpty ?
            descPlaceholder :
                isSlf ?
                NSLocalizedString("Notes, messages, links, files saved for posterity", comment: "Explanation for Saved messages topic") :
                topic.pub?.note
        topicDescriptionTextView.textContainer.maximumNumberOfLines = 2
        topicDescriptionTextView.textContainer.lineBreakMode = .byTruncatingTail
        topicDescriptionTextView.sizeToFit()

        if isSlf {
            topicPrivateTextView.isHidden = true
        } else {
            topicPrivateTextView.isHidden = false
            topicPrivateTextView.textColor = (topic.comment ?? "").isEmpty ? .placeholderText : .secondaryLabel
            topicPrivateTextView.text = (topic.comment ?? "").isEmpty ? NSLocalizedString("Private info: not set", comment: "Placeholder text in editor") : topic.comment
            topicPrivateTextView.sizeToFit()
        }

        topicIDLabel.text = topic.name
        topicIDLabel.sizeToFit()

        if let alias = topic.alias {
            aliasLabel.text = "@\(alias)"
            aliasLabel.sizeToFit()
        }

        avatarImage.set(pub: topic.pub, id: topic.name, deleted: topic.deleted)
        avatarImage.letterTileFont = self.avatarImage.letterTileFont.withSize(CGFloat(50))

        mutedSwitch.isOn = topic.isMuted
        archivedSwitch.isOn = topic.isArchived

        if topic.online {
            self.lastSeenTimestampLabel?.text = NSLocalizedString("online now", comment: "The topic or user is currently online")
        } else if let ts = topic?.lastSeen?.when {
            var date: String
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            date = formatter.localizedString(for: ts, relativeTo: Date())

            self.lastSeenTimestampLabel?.text = date
        }

        if self.topic.isGrpType {
            subscriptions = topic.getSubscriptions()
            // FIXME: reload just the members section.
            tableView.reloadData()
        }
    }
    
    @IBAction func mutedSwitched(_ sender: Any) {
        let isChecked = mutedSwitch.isOn
        topic.updateMuted(muted: isChecked).then(
            onSuccess: UiUtils.ToastSuccessHandler,
            onFailure: { err in
                DispatchQueue.main.async {
                    self.mutedSwitch.isOn = !isChecked
                    if let e = err as? TinodeError, case .notConnected(_) = e {
                        UiUtils.showToast(message: NSLocalizedString("You are offline.", comment: "Toast notification"))
                    }
                }
                return nil
            }).thenFinally({
                DispatchQueue.main.async { self.reloadData() }
            })
    }

    @IBAction func archivedSwitched(_ sender: Any) {
        let isChecked = archivedSwitch.isOn
        topic.updateArchived(archived: isChecked)?.then(
            onSuccess: UiUtils.ToastSuccessHandler,
            onFailure: { err in
                DispatchQueue.main.async {
                    self.archivedSwitch.isOn = !isChecked
                    if let e = err as? TinodeError, case .notConnected(_) = e {
                        UiUtils.showToast(message: NSLocalizedString("You are offline.", comment: "Toast notification"))
                    }
                }
                return nil
            }).thenFinally({
                DispatchQueue.main.async { self.reloadData() }
            })
    }

    /// Copy topic ID or Alias.
    @IBAction func copyTopicValue(_ sender: UIButton) {
        UIPasteboard.general.string = sender.tag == 0 ? topic.name : topic.alias
        UiUtils.showToast(message: sender.tag == 0 ?
                            NSLocalizedString("Address copied", comment: "Toast notification") :
                            NSLocalizedString("Alias copied", comment: "Toast notification"),
                          level: .info)
    }


    @IBAction func showTopicIDQRCode(_ sender: Any) {
        let alert = UIAlertController(title: "Scan QR code", message: "\n\n\n\n\n\n\n\n", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        let qrcode = UIImageView(image: Utils.generateQRCode(from: Utils.kTopicUriPrefix + topic.name))
        alert.view.addSubview(qrcode)
        qrcode.translatesAutoresizingMaskIntoConstraints = false
        alert.view.addConstraint(NSLayoutConstraint(item: qrcode, attribute: .centerX, relatedBy: .equal, toItem: alert.view, attribute: .centerX, multiplier: 1, constant: 0))
        alert.view.addConstraint(NSLayoutConstraint(item: qrcode, attribute: .centerY, relatedBy: .equal, toItem: alert.view, attribute: .centerY, multiplier: 1, constant: 0))
        alert.view.addConstraint(NSLayoutConstraint(item: qrcode, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: 128.0))
        alert.view.addConstraint(NSLayoutConstraint(item: qrcode, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: 128.0))
        self.present(alert, animated: true, completion: nil)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
        case "TopicInfo2EditMembers":
            let navigator = segue.destination as! UINavigationController
            let destination = navigator.viewControllers.first as! EditMembersViewController
            destination.delegate = self
        case "TopicInfo2TopicSecurity":
            let destinationVC = segue.destination as! TopicSecurityViewController
            destinationVC.topicName = self.topicName
        case "TopicInfo2TopicGeneral":
            let destinationVC = segue.destination as! TopicGeneralViewController
            destinationVC.topicName = self.topicName
        default:
            break
        }
    }

    private func promiseSuccessHandler(msg: ServerMessage?) throws -> PromisedReply<ServerMessage>? {
        DispatchQueue.main.async { self.reloadData() }
        return nil
    }
}

extension TopicInfoViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return UIModalPresentationStyle.none
    }
}

extension TopicInfoViewController {
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == TopicInfoViewController.kSectionMembers {
            return showGroupMembers ? (subscriptions?.count ?? 0) + 1 : 0
        }
        return super.tableView(tableView, numberOfRowsInSection: section)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == TopicInfoViewController.kSectionMembers && indexPath.row != 0 {
            return 60
        } else if indexPath.section == TopicInfoViewController.kSectionBasic {
            if indexPath.row == TopicInfoViewController.kSectionBasicLastSeen && topic?.lastSeen == nil {
                return CGFloat.leastNonzeroMagnitude
            }
        } else if indexPath.section == TopicInfoViewController.kSectionExtended {
            if (indexPath.row == TopicInfoViewController.kSectionExtendedPrivate && (topic.comment ?? "").isEmpty) ||
                (indexPath.row == TopicInfoViewController.kSectionExtendedDescription && (topic.pub?.note?.isEmpty ?? true)) ||
                (indexPath.row == TopicInfoViewController.kSectionExtendedAddress && topic.isSlfType) ||
                (indexPath.row == TopicInfoViewController.kSectionExtendedAlias && (topic.alias ?? "").isEmpty) ||
                (indexPath.row == TopicInfoViewController.kSectionExtendedVerified && !(topic?.isVerified ?? false)) ||
                (indexPath.row == TopicInfoViewController.kSectionExtendedStaff && !(topic?.isStaffManaged ?? false)) ||
                (indexPath.row == TopicInfoViewController.kSectionExtendedDanger && !(topic?.isDangerous ?? false)) {
                return CGFloat.leastNonzeroMagnitude
            }
        } else if indexPath.section == TopicInfoViewController.kSectionQuickAction {
            if (indexPath.row == TopicInfoViewController.kSectionQuickActionMute && topic.isSlfType) {
                return CGFloat.leastNonzeroMagnitude
            }
        }

        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == TopicInfoViewController.kSectionMembers && !showGroupMembers {
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
        var cell: UITableViewCell!
        defer {
            // Hide separator lines in the top sections.
            if indexPath.section == TopicInfoViewController.kSectionBasic {
                cell.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: UIScreen.main.bounds.width)
            }
        }

        if indexPath.section != TopicInfoViewController.kSectionMembers {
            cell = super.tableView(tableView, cellForRowAt: indexPath)
        } else if indexPath.row == 0 {
            // Row with [Add members] and [Leave] buttons.
            cell = super.tableView(tableView, cellForRowAt: indexPath)
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ContactViewCell", for: indexPath) as! ContactViewCell

            // Configure the cell...
            let sub = subscriptions![indexPath.row - 1]
            let uid = sub.user
            let isMe = self.tinode.isMe(uid: uid)
            let pub = sub.pub

            cell.avatar.set(pub: pub, id: uid, deleted: false)
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
                    cell.statusLabels[i].textInsets = UIEdgeInsets(top: 3.0, left: 3.0, bottom: 1.5, right: 1.5)
                    cell.statusLabels[i].textColor = accessLabels[i].color
                    cell.statusLabels[i].layer.borderWidth = 1
                    cell.statusLabels[i].layer.borderColor = accessLabels[i].color.cgColor
                    cell.statusLabels[i].sizeToFit()
                }
            }
            cell.accessoryType = isMe ? .none : .disclosureIndicator

            return cell
        }

        return cell
    }

    enum MemberActions {
        case remove, ban
    }
    private func showConfirmationDialog(forAction memberAction: MemberActions, withUid uid: String?,
                                        message: String) {
        guard let uid = uid else { return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert action"), style: .default, handler: { _ in
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
        tableView.deselectRow(at: indexPath, animated: true)

        guard indexPath.section == TopicInfoViewController.kSectionMembers && indexPath.row != 0 else {
            return
        }

        let sub = subscriptions![indexPath.row - 1]
        if self.tinode.isMe(uid: sub.user) {
            return
        }

        let alert = UIAlertController(title: sub.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name"), message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Send message", comment: "Alert action"), style: .default, handler: { _ in
            if let topic = sub.user {
                self.presentChatReplacingCurrentVC(with: topic)
            } else {
                UiUtils.showToast(message: NSLocalizedString("Topic name missing", comment: "Toast notification"))
            }
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Change permissions", comment: "Alert action"), style: .default, handler: { _ in
            guard let acsUnwrapped = sub.acs?.given, acsUnwrapped.isDefined else {
                UiUtils.showToast(message: NSLocalizedString("Can't change permissions for this user.", comment: "Toast notification"))
                return
            }
            UiUtils.showPermissionsEditDialog(over: self, acs: acsUnwrapped, callback: { perm in
                    UiUtils.handlePermissionsChange(onTopic: self.topic, forUid: sub.user, changeType: .updateSub, newPermissions: perm)?.then(onSuccess: self.promiseSuccessHandler) }, disabledPermissions: nil)
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Make owner", comment: "Alert action"), style: .default, handler: { _ in
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
        alert.addAction(UIAlertAction(title: NSLocalizedString("Remove", comment: "Alert action"), style: .default, handler: { _ in
            self.showConfirmationDialog( forAction: .remove, withUid: sub.user, message: String(format: NSLocalizedString("Remove %@ from %@?", comment: "Confirmation"), title, topicTitle))
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Block", comment: "Alert action"), style: .default, handler: { _ in
            self.showConfirmationDialog(forAction: .ban, withUid: sub.user, message: String(format: NSLocalizedString("Remove and ban %@ from %@?", comment: "Confirmation"), title, topicTitle))
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
}

extension TopicInfoViewController: EditMembersDelegate {
    func editMembersInitialSelection(_: UIView) -> [ContactHolder] {
        return subscriptions?.compactMap {
            return ContactHolder(pub: $0.pub, uniqueId: $0.user)
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
