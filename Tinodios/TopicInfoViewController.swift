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
    @IBOutlet weak var avatarImage: RoundImageView!
    @IBOutlet weak var loadAvatarButton: UIButton!
    @IBOutlet weak var mutedSwitch: UISwitch!
    @IBOutlet weak var topicIDLabel: UILabel!
    @IBOutlet weak var permissionsLabel: UILabel!
    @IBOutlet weak var myPermissionsLabel: UILabel!
    @IBOutlet weak var peerPermissionsLabel: UILabel!
    @IBOutlet weak var authUsersPermissionsLabel: UILabel!
    @IBOutlet weak var anonUsersPermissionsLabel: UILabel!
    @IBOutlet weak var groupView: UIView!

    var topicName = ""
    var topic: DefaultComTopic!
    var tinode: Tinode!

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    private func setup() {
        self.tinode = Cache.getTinode()
        self.topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic
        self.topicTitleTextView.text = self.topic.pub?.fn ?? "Unknown"
        self.topicIDLabel.text = self.topic?.name
        self.topicIDLabel.sizeToFit()
        if let avatar = topic.pub?.photo?.image() {
            self.avatarImage.image = avatar
        }
        if !self.topic.isGrpType {
            self.loadAvatarButton.isHidden = true
            self.groupView.isHidden = true
        }
    }
}
