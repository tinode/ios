//
//  TopicInfoViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

class TopicInfoViewController: UITableViewController {

    @IBOutlet weak var topicTitleTextView: UITextView!
    @IBOutlet weak var topicSubtitleTextView: UITextView!
    @IBOutlet weak var avatarImage: RoundImageView!
    @IBOutlet weak var loadAvatarButton: UIButton!
    @IBOutlet weak var mutedSwitch: UISwitch!
    @IBOutlet weak var topicIDLabel: UILabel!
    @IBOutlet weak var permissionsLabel: UILabel!
    @IBOutlet weak var myPermissionsLabel: UILabel!
    @IBOutlet weak var peerNameLabel: UILabel!
    @IBOutlet weak var peerPermissionsLabel: UILabel!
    @IBOutlet weak var authUsersPermissionsLabel: UILabel!
    @IBOutlet weak var anonUsersPermissionsLabel: UILabel!
    @IBOutlet weak var groupView: UIView!
    @IBOutlet weak var p2pPermissionsView: UIView!
    @IBOutlet weak var defaultPermissionsView: UIView!
    @IBOutlet weak var membersTableView: UITableView!

    var topicName = ""
    private var topic: DefaultComTopic!
    private var tinode: Tinode!
    private var imagePicker: ImagePicker!

    private var subscriptions: [Subscription<VCard, PrivateType>]?

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    override func viewDidAppear(_ animated: Bool) {
        reloadData()
    }
    // Hides view and sets its height to 0.
    private static func collapseView(view: UIView) {
        view.isHidden = true
        view.subviews.forEach({ $0.removeFromSuperview() })
        view.frame = CGRect(x: 0 , y: 0, width: view.frame.width, height: 0)
    }
    private func setup() {
        self.tinode = Cache.getTinode()
        self.topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic
        guard self.topic != nil else {
            return
        }

        var p2pPermissionsViewActive = true
        var defaultPermissionsViewActive = true
        if self.topic.isGrpType {
            self.loadAvatarButton.isHidden = !topic.isManager
            defaultPermissionsViewActive = topic.isManager
            self.defaultPermissionsView.isHidden = !defaultPermissionsViewActive
            if !defaultPermissionsViewActive {
                TopicInfoViewController.collapseView(view: self.defaultPermissionsView)
            }
            p2pPermissionsViewActive = false
            TopicInfoViewController.collapseView(view: self.p2pPermissionsView)

            self.membersTableView.dataSource = self
            self.membersTableView.allowsMultipleSelection = true
            self.membersTableView.delegate = self
            self.membersTableView.register(UINib(nibName: "ContactViewCell", bundle: nil), forCellReuseIdentifier: "ContactViewCell")
            self.membersTableView.allowsSelection = false
        } else {
            self.loadAvatarButton.isHidden = true
            self.groupView.isHidden = true
            self.defaultPermissionsView.isHidden = true
            self.permissionsLabel.isHidden = true
            defaultPermissionsViewActive = false
            TopicInfoViewController.collapseView(view: self.defaultPermissionsView)
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
        if p2pPermissionsViewActive {
            UiUtils.setupTapRecognizer(
                forView: myPermissionsLabel,
                action: #selector(TopicInfoViewController.permissionsTapped),
                actionTarget: self)
            UiUtils.setupTapRecognizer(
                forView: peerPermissionsLabel,
                action: #selector(TopicInfoViewController.permissionsTapped),
                actionTarget: self)
        }
        if defaultPermissionsViewActive {
            UiUtils.setupTapRecognizer(
                forView: authUsersPermissionsLabel,
                action: #selector(TopicInfoViewController.permissionsTapped),
                actionTarget: self)
            UiUtils.setupTapRecognizer(
                forView: anonUsersPermissionsLabel,
                action: #selector(TopicInfoViewController.permissionsTapped),
                actionTarget: self)
        }
        UiUtils.setupTapRecognizer(
            forView: permissionsLabel,
            action: #selector(TopicInfoViewController.permissionsTapped),
            actionTarget: self)
        self.imagePicker = ImagePicker(
            presentationController: self, delegate: self)
    }
    private func reloadData() {
        self.topicTitleTextView.text = self.topic.pub?.fn ?? "Unknown"
        self.topicIDLabel.text = self.topic?.name
        self.topicIDLabel.sizeToFit()
        let subtitle = self.topic.comment ?? ""
        self.topicSubtitleTextView.text = !subtitle.isEmpty ? subtitle : "Private info: not set"
        self.avatarImage.set(icon: topic.pub?.photo?.image(), title: topic.pub?.fn, id: topic?.name)
        self.avatarImage.letterTileFont = self.avatarImage.letterTileFont.withSize(CGFloat(50))
        self.mutedSwitch.isOn = self.topic.isMuted
        let acs = self.topic.accessMode
        self.permissionsLabel.text = acs?.modeString
        if self.topic.isGrpType {
            self.authUsersPermissionsLabel?.text = self.topic.defacs?.getAuth()
            self.anonUsersPermissionsLabel?.text = self.topic.defacs?.getAnon()

            self.subscriptions = self.topic.getSubscriptions()
            self.membersTableView.reloadData()
        } else {
            self.peerNameLabel?.text = self.topic.pub?.fn ?? "Unknown"
            self.myPermissionsLabel?.text = acs?.wantString
            let sub = self.topic.getSubscription(for: self.topic.name)
            self.peerPermissionsLabel?.text = sub?.acs?.givenString
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
                    return nil
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
    private func getAcsAndPermissionsChangeType(for sender: UIView)
        -> (AcsHelper?, String?, UiUtils.PermissionsChangeType?, [PermissionsEditViewController.PermissionType]?) {
        if sender === myPermissionsLabel {
            return (topic.accessMode?.want, nil, .updateSelfSub, [.approve, .invite, .delete])
        }
        if sender === peerPermissionsLabel {
            return (self.topic.getSubscription(for: self.topic.name)?.acs?.given,
                    topic.name, .updateSub, [.approve, .invite, .delete])
        }
        if sender === authUsersPermissionsLabel {
            return (topic.defacs?.auth, nil, .updateAuth, nil)  // Should be O?
        }
        if sender == anonUsersPermissionsLabel {
            return (topic.defacs?.anon, nil, .updateAnon, nil)  // Should be O?
        }
        if sender == permissionsLabel {
            return (topic.accessMode?.want, nil, .updateSelfSub, nil)  // Should be O?
        }
        return (nil, nil, nil, nil)
    }
    private func changePermissions(
        acs: AcsHelper, uid: String?,
        changeType: UiUtils.PermissionsChangeType,
        disabledPermissions: [PermissionsEditViewController.PermissionType]?) {
        UiUtils.showPermissionsEditDialog(
            over: self, acs: acs,
            callback: {
                permissionsTuple in
                _ = try? UiUtils.handlePermissionsChange(
                    onTopic: self.topic, forUid: uid, changeType: changeType,
                    permissions: permissionsTuple)?.then(
                        onSuccess: self.promiseSuccessHandler)},
            disabledPermissions: disabledPermissions)
    }
    @objc
    func permissionsTapped(sender: UITapGestureRecognizer) {
        guard let v = sender.view else {
            print("Tap from no sender view... quitting")
            return
        }
        let (acs, uid, changeTypeOptional, disablePermissions) = getAcsAndPermissionsChangeType(for: v)
        guard let acsUnwrapped = acs, let changeType = changeTypeOptional else {
            print("could not get acs")
            return
        }
        self.changePermissions(acs: acsUnwrapped, uid: uid,
                               changeType: changeType, disabledPermissions: disablePermissions)
    }
    @IBAction func leaveGroupClicked(_ sender: Any) {
        if topic.isOwner {
            UiUtils.showToast(message: "Owner cannot unsubscribe")
        } else {
            do {
                try topic.delete()?.then(
                    onSuccess: { msg in
                        DispatchQueue.main.async {
                            self.navigationController?.popViewController(animated: true)
                            self.dismiss(animated: true, completion: nil)
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
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "TopicInfo2EditMembers" {
            let destinationVC = segue.destination as! EditMembersViewController
            destinationVC.topicName = self.topicName
        }
    }
    private func promiseSuccessHandler(msg: ServerMessage) throws -> PromisedReply<ServerMessage>? {
        DispatchQueue.main.async { self.reloadData() }
        return nil
    }
}

extension TopicInfoViewController: UITableViewDataSource, UITableViewDelegate {

    // MARK: - Table view data source
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return subscriptions?.count ?? 0
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

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ContactViewCell", for: indexPath) as! ContactViewCell

        // Configure the cell...
        let sub = subscriptions![indexPath.row]
        let uid = sub.user
        let isMe = self.tinode.isMe(uid: uid)
        let pub = sub.pub
        let displayName = isMe ? "You" : (pub?.fn ?? "Unknown")

        cell.avatar.set(icon: pub?.photo?.image(), title: displayName, id: uid)
        cell.title.text = displayName
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
        cell.accessoryType = isMe ? .none : .detailDisclosureButton

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

    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let sub = subscriptions![indexPath.row]
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
            self.changePermissions(acs: acsUnwrapped, uid: sub.user,
                                   changeType: .updateSub, disabledPermissions: [])

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

extension TopicInfoViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?) {
        guard let image = image else {
            print("No image specified - skipping")
            return
        }
        _ = try? UiUtils.updateAvatar(forTopic: self.topic, image: image)?.then(
            onSuccess: self.promiseSuccessHandler)
    }
}
