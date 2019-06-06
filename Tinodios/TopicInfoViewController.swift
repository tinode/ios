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
