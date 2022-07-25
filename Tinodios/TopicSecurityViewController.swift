//
//  TopicSecurityViewController.swift
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

class TopicSecurityViewController: UITableViewController {
    private static let kSectionActions = 0
    private static let kSectionActionsDelMessages = 0
    private static let kSectionActionsLeaveGroup = 1
    private static let kSectionActionsLeaveConversation = 2
    private static let kSectionActionsDelTopic = 3
    private static let kSectionActionsBlock = 4
    private static let kSectionActionsReport = 5
    private static let kSectionActionsReportGroup = 6

    private static let kSectionPermissions = 1
    private static let kSectionPermissionsMine = 0
    private static let kSectionPermissionsPeer = 1

    private static let kSectionDefaultPermissions = 2
    private static let kSectionDefaultPermissionsAuth = 0
    private static let kSectionDefaultPermissionsAnon = 1

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
    @IBOutlet weak var actionBlockContact: UITableViewCell!
    @IBOutlet weak var actionReportContact: UITableViewCell!
    @IBOutlet weak var actionReportGroup: UITableViewCell!

    var topicName = ""
    private var topic: DefaultComTopic!
    private var tinode: Tinode!

    // Show row with Peer's permissions (p2p topic)
    private var showPeerPermissions: Bool = false
    // Show section with default topic permissions (manager of a grp topic)
    private var showDefaultPermissions: Bool = false

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
            showDefaultPermissions = topic.isManager
            showPeerPermissions = false
        } else {
            showDefaultPermissions = false
            showPeerPermissions = true
        }

        UiUtils.setupTapRecognizer(
            forView: actionDeleteMessages,
            action: #selector(TopicSecurityViewController.deleteMessagesClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionDeleteGroup,
            action: #selector(TopicSecurityViewController.deleteGroupClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionLeaveGroup,
            action: #selector(TopicSecurityViewController.leaveGroupClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionLeaveConversation,
            action: #selector(TopicSecurityViewController.leaveConversationClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionBlockContact,
            action: #selector(TopicSecurityViewController.blockContactClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionReportContact,
            action: #selector(TopicSecurityViewController.reportContactClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionReportGroup,
            action: #selector(TopicSecurityViewController.reportGroupClicked),
            actionTarget: self)

        UiUtils.setupTapRecognizer(
            forView: actionMyPermissions,
            action: #selector(TopicSecurityViewController.permissionsTapped),
            actionTarget: self)

        if showPeerPermissions {
            UiUtils.setupTapRecognizer(
                forView: actionPeerPermissions,
                action: #selector(TopicSecurityViewController.permissionsTapped),
                actionTarget: self)
        }

        if showDefaultPermissions {
            UiUtils.setupTapRecognizer(
                forView: actionAuthPermissions,
                action: #selector(TopicSecurityViewController.permissionsTapped),
                actionTarget: self)
            UiUtils.setupTapRecognizer(
                forView: actionAnonPermissions,
                action: #selector(TopicSecurityViewController.permissionsTapped),
                actionTarget: self)
        }
    }

    private func reloadData() {
        let acs = topic.accessMode

        if self.topic.isGrpType {
            authUsersPermissionsLabel?.text = topic.defacs?.getAuth()
            anonUsersPermissionsLabel?.text = topic.defacs?.getAnon()
            myPermissionsLabel?.text = acs?.modeString
            // FIXME: reload just the members section.
            tableView.reloadData()
        } else {
            peerNameLabel?.text = topic.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name")
            myPermissionsLabel?.text = acs?.wantString
            let sub = topic.getSubscription(for: self.topic.name)
            peerPermissionsLabel?.text = sub?.acs?.givenString
        }
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
                UiUtils.showPermissionsEditDialog(over: self, acs: acs.want, callback: { perm in UiUtils.handlePermissionsChange(onTopic: self.topic, forUid: nil, changeType: .updateSelfSub, newPermissions: perm)?.then(onSuccess: self.promiseSuccessHandler) }, disabledPermissions: disabled)
            } else {
                Cache.log.error("Access mode is nil")
            }
        case actionPeerPermissions:
            UiUtils.showPermissionsEditDialog(over: self, acs: topic.getSubscription(for: self.topic.name)?.acs?.given, callback: { perm in UiUtils.handlePermissionsChange(onTopic: self.topic, forUid: self.topic.name, changeType: .updateSub, newPermissions: perm)?.then(onSuccess: self.promiseSuccessHandler) }, disabledPermissions: "ASDO")
        case actionAuthPermissions:
            UiUtils.showPermissionsEditDialog(over: self, acs: topic.defacs?.auth, callback: { perm in UiUtils.handlePermissionsChange(onTopic: self.topic, forUid: nil, changeType: .updateAuth, newPermissions: perm)?.then(onSuccess: self.promiseSuccessHandler) }, disabledPermissions: "O")
        case actionAnonPermissions:
            UiUtils.showPermissionsEditDialog(over: self, acs: topic.defacs?.anon, callback: { perm in UiUtils.handlePermissionsChange(onTopic: self.topic, forUid: nil, changeType: .updateAnon, newPermissions: perm)?.then(onSuccess: self.promiseSuccessHandler) }, disabledPermissions: "O")
        default:
            return
        }
    }

    private func deleteTopic() {
        topic.delete(hard: true).then(
            onSuccess: { _ in
                DispatchQueue.main.async {
                    self.performSegue(withIdentifier: "TopicSecurity2Chats", sender: nil)
                }
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler)
    }

    private func blockContact() {
        topic.updateMode(uid: nil, update: "-JP").then(
            onSuccess: { _ in
                DispatchQueue.main.async {
                    self.performSegue(withIdentifier: "TopicSecurity2Chats", sender: nil)
                }
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler)
    }

    private func reportTopic(reason: String) {
        blockContact()
        // Create and send spam report.
        let msg = Drafty().attachJSON([
            "action": JSONValue.string("report"),
            "target": JSONValue.string(self.topic.name)
            ])
        _ = Cache.tinode.publish(topic: Tinode.kTopicSys, head: ["mime": .string(Drafty.kJSONMimeType)], content: msg, attachments: nil)
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
            handler: { _ in self.deleteTopic() }))
        present(alert, animated: true)
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
                handler: { _ in handler(true) }))
        }
        alert.addAction(UIAlertAction(
            title: topic.isDeleter ? NSLocalizedString("For me", comment: "Alert action 'Delete for me'") : NSLocalizedString("OK", comment: "Alert action"), style: .destructive,
            handler: { _ in handler(false) }))
        present(alert, animated: true)
    }

    @objc func leaveConversationClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("Leave the conversation?", comment: "Alert title"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Leave", comment: "Alert action"), style: .destructive,
            handler: { _ in self.deleteTopic() }))
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
            handler: { _ in self.deleteTopic() }))
        present(alert, animated: true)
    }

    @objc func blockContactClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("Block contact?", comment: "Alert action"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Block", comment: "Alert action"), style: .destructive,
            handler: { _ in self.blockContact() }))
        present(alert, animated: true)
    }

    @objc func reportContactClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("Report contact?", comment: "Alert title"), message: NSLocalizedString("Also block and remove all messages", comment: "Alert explanation"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Report", comment: "Alert action"), style: .destructive,
            handler: { _ in self.reportTopic(reason: "TODO") }))
        present(alert, animated: true)
    }

    @objc func reportGroupClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("Report Group?", comment: "Alert title"), message: NSLocalizedString("Also block and remove all messages", comment: "Alert explanation"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Report", comment: "Alert action"), style: .destructive,
            handler: { _ in self.reportTopic(reason: "TODO") }))
        present(alert, animated: true)
    }

    private func promiseSuccessHandler(msg: ServerMessage?) throws -> PromisedReply<ServerMessage>? {
        Cache.log.debug("promiseSuccessHandler - update succeseeded")
        DispatchQueue.main.async { self.reloadData() }
        return nil
    }
}

extension TopicSecurityViewController {
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {

        if section == TopicSecurityViewController.kSectionDefaultPermissions && !showDefaultPermissions {
            return 0
        }
        if section == TopicSecurityViewController.kSectionPermissions && !showPeerPermissions {
            return 1
        }
        return super.tableView(tableView, numberOfRowsInSection: section)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == TopicSecurityViewController.kSectionActions {
            if indexPath.row == TopicSecurityViewController.kSectionActionsDelMessages && (topic?.isChannel ?? false) {
                // Channel readers cannot delete messages
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicSecurityViewController.kSectionActionsLeaveGroup && !(topic?.isGrpType ?? false) {
                // P2P topic, hide [Leave Group]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicSecurityViewController.kSectionActionsLeaveConversation && topic?.isGrpType ?? false {
                // Group topic, hide [Leave Conversation]
                return CGFloat.leastNonzeroMagnitude
            }
            // Hide either [Leave] or [Delete Topic] actions.
            if indexPath.row == TopicSecurityViewController.kSectionActionsLeaveGroup && topic?.isOwner ?? false {
                // Owner, hide [Leave]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicSecurityViewController.kSectionActionsDelTopic && !(topic?.isOwner ?? false) {
                // Not an owner, hide [Delete Topic]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicSecurityViewController.kSectionActionsBlock && topic?.isGrpType ?? false {
                // Group topic, hide [Block Contact]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicSecurityViewController.kSectionActionsReport && topic?.isGrpType ?? false {
                // Group topic, hide [Report Contact]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicSecurityViewController.kSectionActionsReportGroup && (!(topic?.isGrpType ?? false) || (topic?.isOwner ?? false)) {
                // P2P topic or the owner, hide [Report Group]
                return CGFloat.leastNonzeroMagnitude
            }
        }

        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == TopicSecurityViewController.kSectionDefaultPermissions && !showDefaultPermissions {
            return nil
        }

        return super.tableView(tableView, titleForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // Hide empty header in the first section.
        if section == TopicSecurityViewController.kSectionActions {
            return CGFloat.leastNormalMagnitude
        }

        if section == TopicSecurityViewController.kSectionDefaultPermissions && !showDefaultPermissions {
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

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
