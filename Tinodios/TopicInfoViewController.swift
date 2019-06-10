//
//  TopicInfoViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

class TopicInfoViewController: UIViewController {

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
        // TODO: use a letter avatar when no image is available.
        if let avatar = topic.pub?.photo?.image() {
            self.avatarImage.image = avatar
        }
        self.mutedSwitch.isOn = self.topic.isMuted
        let acs = self.topic.accessMode
        self.permissionsLabel.text = acs?.modeString
        if self.topic.isGrpType {
            self.authUsersPermissionsLabel.text = self.topic.defacs?.getAuth()
            self.anonUsersPermissionsLabel.text = self.topic.defacs?.getAnon()

            self.subscriptions = self.topic.getSubscriptions()
        } else {
            self.peerNameLabel.text = self.topic.pub?.fn ?? "Unknown"
            self.myPermissionsLabel.text = self.topic.accessMode?.wantString
            self.peerPermissionsLabel.text = self.topic.accessMode?.givenString
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
            return (topic.accessMode?.given, topic.name, .updateSub, [.approve, .invite, .delete])
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
        UiUtils.showPermissionsEditDialog(
            over: self, acs: acsUnwrapped,
            callback: {
                permissionsTuple in
                _ = try? UiUtils.handlePermissionsChange(
                    onTopic: self.topic, forUid: uid, changeType: changeType,
                    permissions: permissionsTuple)?.then(
                        onSuccess: { msg in
                            DispatchQueue.main.async { self.reloadData() }
                            return nil
                    }
                )},
            disabledPermissions: disablePermissions)
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
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ContactViewCell", for: indexPath) as! ContactViewCell

        // Configure the cell...
        let sub = subscriptions![indexPath.row]

        let pub = sub.pub
        let displayName = pub?.fn ?? "Unknown"
        let uid = sub.uniqueId
        cell.avatar.set(icon: pub?.photo?.image(), title: displayName, id: uid)
        cell.title.text = displayName
        cell.title.sizeToFit()
        if let acs = sub.acs {
            if acs.isModeDefined && acs.isOwner {
                cell.status.isHidden = false
                cell.status.text = "owner"
                cell.status.sizeToFit()
                cell.status.textInsets = UIEdgeInsets(top: CGFloat(7), left: CGFloat(7), bottom: CGFloat(5), right: CGFloat(5))
                //0xFF4CAF50
                let green = UIColor(red: 0x4c / 255.0, green: 0xaf / 255.0, blue: 0x50 / 255.0, alpha: 1.0)
                cell.status.textColor = green
                cell.status.layer.borderWidth = 1
                cell.status.layer.borderColor = green.cgColor
            }
        }

        return cell
    }
}

extension TopicInfoViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?) {
        guard let image = image else {
            print("No image specified - skipping")
            return
        }
        _ = try? UiUtils.updateAvatar(forTopic: self.topic, image: image)?.then(
            onSuccess: { msg in
                DispatchQueue.main.async { self.reloadData() }
                return nil
            }
        )
    }
}
