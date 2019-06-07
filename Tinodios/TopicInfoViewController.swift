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
    private func setup() {
        self.tinode = Cache.getTinode()
        self.topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic

        if self.topic.isGrpType {
            self.loadAvatarButton.isHidden = !topic.isManager
            self.defaultPermissionsView.isHidden = !topic.isManager
            self.p2pPermissionsView.isHidden = true

            self.membersTableView.dataSource = self
            self.membersTableView.allowsMultipleSelection = true
            self.membersTableView.delegate = self
            self.membersTableView.register(UINib(nibName: "ContactViewCell", bundle: nil), forCellReuseIdentifier: "ContactViewCell")

        } else {
            self.loadAvatarButton.isHidden = true
            self.groupView.isHidden = true
            self.defaultPermissionsView.isHidden = true
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
            forView: myPermissionsLabel,
            action: #selector(TopicInfoViewController.permissionsTapped),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: peerPermissionsLabel,
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
    // TODO: Fold it down to UiUtils.
    @objc
    func permissionsTapped(sender: UITapGestureRecognizer) {
        guard let v = sender.view else {
            print("Tap from no sender view... quitting")
            return
        }
        var acs: AcsHelper? = nil
        if v === myPermissionsLabel {
            acs = topic.accessMode?.want
        } else if v == peerPermissionsLabel {
            acs = topic.accessMode?.given
        }
        guard let acsUnwrapped = acs else {
            print("could not get acs")
            return
        }
        let alertVC = PermissionsEditViewController(
            joinState: acsUnwrapped.hasPermissions(forMode: AcsHelper.kModeJoin),
            readState: acsUnwrapped.hasPermissions(forMode: AcsHelper.kModeRead),
            writeState: acsUnwrapped.hasPermissions(forMode: AcsHelper.kModeWrite),
            notificationsState: acsUnwrapped.hasPermissions(forMode: AcsHelper.kModePres),
            approveState: acsUnwrapped.hasPermissions(forMode: AcsHelper.kModeApprove),
            inviteState: acsUnwrapped.hasPermissions(forMode: AcsHelper.kModeShare),
            deleteState: acsUnwrapped.hasPermissions(forMode: AcsHelper.kModeDelete),
            disabledPermissions: [.approve, .invite, .delete],
            onChangeHandler: { [v]
                joinState,
                readState,
                writeState,
                notificationsState,
                approveState,
                inviteState,
                deleteState in
                self.didChangePermissions(
                    forLabel: v,
                    joinState: joinState,
                    readState: readState,
                    writeState: writeState,
                    notificationsState: notificationsState,
                    approveState: approveState,
                    inviteState: inviteState,
                    deleteState: deleteState)
        })
        alertVC.show(over: self)
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
                DispatchQueue.main.async {
                    self.reloadData()
                }
                return nil
            }
        )
    }
}
extension TopicInfoViewController {
    func didChangePermissions(forLabel l: UIView,
                              joinState: Bool,
                              readState: Bool,
                              writeState: Bool,
                              notificationsState: Bool,
                              approveState: Bool,
                              inviteState: Bool,
                              deleteState: Bool) {
    }
}
